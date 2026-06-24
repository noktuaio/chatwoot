module Crm
  module Meetings
    # Resolves a mailbox's busy intervals for a single local day so the scheduler
    # can mark conflicting slots. Channel/provider aware (Google /freeBusy vs
    # Microsoft getSchedule), cached per inbox+date, and fail-safe — any error
    # returns [] so availability never blocks scheduling.
    class AvailabilityService
      CACHE_TTL = 15.minutes
      # Deterministic simulated busy block (12:00–13:00 local) used when the
      # provider is simulated, so the FE can be exercised without a real call.
      SIM_BUSY_START_HOUR = 12
      SIM_BUSY_END_HOUR = 13

      def initialize(inbox:, date:, timezone:, agent: nil)
        @inbox = inbox
        @date = date
        @timezone = timezone
        @agent = agent
      end

      # Cache key includes timezone — the same inbox+date covers a different UTC
      # window per timezone, so they must not share a cache entry.
      def self.cache_key_for(inbox_id:, date:, timezone:)
        "crm_meeting_availability:#{inbox_id}:#{date}:#{timezone.presence || 'UTC'}"
      end

      # Drop the cached availability for a mailbox/day so a meeting just
      # created/rescheduled/canceled is reflected immediately (instead of staying
      # stale for up to CACHE_TTL). Called from the meeting create/reschedule/cancel
      # services for the affected inbox + local day(s).
      def self.invalidate(inbox_id:, date:, timezone:)
        return if inbox_id.blank? || date.blank?

        Rails.cache.delete(cache_key_for(inbox_id: inbox_id, date: date, timezone: timezone))
      end

      # Returns an array of { start:, end: } (ISO8601 strings).
      #
      # strict:false (default) — fail-safe + 15-min cached: any provider error
      #   degrades to [] (fine for DISPLAY, where a transient error must not block
      #   the page). strict:true — used at BOOKING time: NEVER serve from cache
      #   (force a fresh provider lookup) and do NOT rescue provider errors (let
      #   them raise) so the caller can fail CLOSED instead of silently allowing a
      #   slot whose true busy state is unknown.
      def busy_intervals(strict: false)
        # SHARED mailbox + a known agent: availability is computed PER AGENT from the
        # CRM's own meetings, NOT the mailbox free/busy (which is everyone's union and
        # would over-block — two sellers can't both lose 14:00 because one is busy).
        # Authoritative DB read, so strict/fail-closed is inherent (no provider call).
        return agent_scoped_intervals if agent_scoped?

        # strict (booking time): fresh, NOT rescued — a provider error propagates so
        # the caller fails CLOSED. Deliberately outside the rescue below. The
        # provider lookup itself is told to raise (raise_on_error) so a non-2xx
        # free/busy response is a real error here, not a silent "no busy".
        return fetch_busy_intervals(strict: true) if strict

        cached_busy_intervals
      end

      private

      # Per-agent availability applies only to a SHARED mailbox AND when we know which
      # agent is booking. A dedicated mailbox (default) keeps the real provider
      # free/busy, so nothing changes for existing single-agent setups.
      def agent_scoped?
        agent.present? && shared_calendar?
      end

      def shared_calendar?
        channel.is_a?(Channel::Email) && channel.calendar_shared?
      end

      # The agent's own scheduled meetings (as HOST), account-wide for the day — an
      # agent can't be in two meetings at once regardless of which mailbox hosts them.
      # Fresh (NOT cached) so a just-booked slot is reflected immediately.
      def agent_scoped_intervals
        Crm::Meeting
          .where(account_id: inbox.account_id, created_by_id: agent.id, status: :scheduled)
          .where('starts_at < ? AND ends_at > ?', local_day.end_of_day, local_day)
          .pluck(:starts_at, :ends_at)
          .map { |start_at, end_at| { start: start_at.iso8601, end: end_at.iso8601 } }
      end

      def cached_busy_intervals
        Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
          fetch_busy_intervals(strict: false)
        end
      rescue StandardError => e
        Rails.logger.error("CRM availability lookup failed: #{e.class.name}")
        []
      end

      attr_reader :inbox, :date, :timezone, :agent

      def cache_key
        self.class.cache_key_for(inbox_id: inbox.id, date: date, timezone: timezone)
      end

      def fetch_busy_intervals(strict: false)
        return [] if channel.blank?

        intervals =
          if simulated?
            simulated_intervals
          else
            provider_intervals(strict: strict)
          end

        intervals.map { |slot| { start: slot[:start].iso8601, end: slot[:end].iso8601 } }
      end

      def provider_intervals(strict: false)
        if channel.microsoft?
          Microsoft::FreeBusyService.new(
            channel: channel,
            time_min: time_min,
            time_max: time_max,
            email: channel.calendar_organizer_email
          ).busy_intervals(raise_on_error: strict)
        else
          Google::FreeBusyService.new(
            channel: channel,
            time_min: time_min,
            time_max: time_max
          ).busy_intervals(raise_on_error: strict)
        end
      end

      def simulated_intervals
        [{ start: local_time(SIM_BUSY_START_HOUR), end: local_time(SIM_BUSY_END_HOUR) }]
      end

      def simulated?
        return Crm::Config.calendar_ms_simulate? if channel.microsoft?

        Crm::Config.calendar_google_simulate?
      end

      def channel
        @channel ||= inbox.channel
      end

      def time_zone
        @time_zone ||= ActiveSupport::TimeZone[timezone.presence || 'UTC'] || ActiveSupport::TimeZone['UTC']
      end

      def local_day
        @local_day ||= time_zone.parse("#{date} 00:00:00")
      end

      def local_time(hour)
        local_day.change(hour: hour)
      end

      def time_min
        local_day
      end

      def time_max
        local_day.end_of_day
      end
    end
  end
end
