# Aggregates the account's OWN external calendar events (Google/Microsoft) for a
# time window so the CRM calendar can render the agent's real availability as
# READ-ONLY context (P2 slice S4). Cached per inbox+window (~30min) in Rails.cache
# so opening the calendar never fans out a live provider call per render.
#
# Honors the per-provider simulate flags (returns a deterministic fake event so
# the harness can render the muted style without a real call), dedupes against
# the account's own CRM meetings (crm_meetings.external_event_id) to avoid
# rendering a meeting twice, and is fail-safe (top-level rescue → []).
module Crm
  module Calendar
    class ExternalEventsService
      pattr_initialize [:account!, :inboxes!, :time_min!, :time_max!]

      CACHE_TTL = 30.minutes
      MAX_EVENTS = 100

      def events
        own_ids = own_external_event_ids
        collected = calendar_inboxes.flat_map { |inbox| events_for_inbox(inbox) }

        collected
          .reject { |event| own_ids.include?(event[:external_id]) }
          .first(MAX_EVENTS)
          .map { |event| calendar_event(event) }
      rescue StandardError => e
        Rails.logger.error("Crm::Calendar::ExternalEventsService failed: #{e.message}")
        []
      end

      private

      def events_for_inbox(inbox)
        # skip_nil + nil-on-provider-failure → a transient provider error is NOT
        # cached for 30min (retries next load), while a genuinely empty calendar
        # ([]) caches normally.
        cached = Rails.cache.fetch(cache_key(inbox), expires_in: CACHE_TTL, skip_nil: true) do
          fetch_for_inbox(inbox)
        end
        Array(cached).map { |event| event.merge(inbox_id: inbox.id, provider: inbox.channel.calendar_provider) }
      end

      def fetch_for_inbox(inbox)
        channel = inbox.channel
        if channel.google?
          return [simulated_event] if Crm::Config.calendar_google_simulate?

          Google::ExternalEventsService.new(channel: channel, time_min: time_min, time_max: time_max).events
        elsif channel.microsoft?
          return [simulated_event] if Crm::Config.calendar_ms_simulate?

          Microsoft::ExternalEventsService.new(channel: channel, time_min: time_min, time_max: time_max).events
        end
      end

      def simulated_for?(inbox)
        channel = inbox.channel
        (channel.google? && Crm::Config.calendar_google_simulate?) ||
          (channel.microsoft? && Crm::Config.calendar_ms_simulate?)
      end

      # Deterministic fake so the harness can render the muted style under a
      # simulate flag without a real provider call: today 10:00–11:00.
      def simulated_event
        start = Time.zone.now.change(hour: 10, min: 0)
        {
          external_id: "sim-external-#{start.to_date.iso8601}",
          title: 'Reunião externa (simulada)',
          starts_at: start.iso8601,
          ends_at: (start + 1.hour).iso8601,
          all_day: false
        }
      end

      # Already Pundit-scoped + calendar-filtered by the controller (admins → all
      # account inboxes, agents → their member inboxes), so an agent never sees
      # another mailbox's external events.
      def calendar_inboxes
        Array(inboxes).select do |inbox|
          channel = inbox.channel
          channel.is_a?(Channel::Email) && channel.calendar_enabled? && (channel.google? || channel.microsoft?)
        end
      end

      def own_external_event_ids
        account.crm_meetings.where.not(external_event_id: nil).pluck(:external_event_id).to_set
      end

      def cache_key(inbox)
        mode = simulated_for?(inbox) ? 'sim' : 'live'
        "crm_external_events:#{inbox.id}:#{time_min.to_i}:#{time_max.to_i}:#{mode}"
      end

      def calendar_event(event)
        {
          id: "ext-#{event[:inbox_id]}-#{event[:external_id]}",
          event_type: 'external',
          title: event[:title],
          starts_at: iso8601(event[:starts_at]),
          ends_at: iso8601(event[:ends_at]),
          all_day: event[:all_day] == true,
          editable: false,
          inbox_id: event[:inbox_id],
          provider: event[:provider]
        }
      end

      def iso8601(value)
        return if value.blank?

        Time.zone.parse(value.to_s).iso8601
      rescue ArgumentError, TypeError
        value
      end
    end
  end
end
