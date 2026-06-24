module Crm
  module Meetings
    # 2-way sync (S7, PULL): reconcile a CRM meeting with the agent's provider
    # calendar (Google / Microsoft). Reads the event ONCE via event_state and:
    #   - deleted/cancelled in the provider -> cancel the CRM meeting LOCALLY
    #     (propagate:false, so we never echo the change back -> no loop),
    #   - time changed in the provider     -> reschedule the CRM meeting LOCALLY,
    #   - attendee responses               -> RSVP (delegated to RsvpSyncService).
    # An :unknown/transient result is a NO-OP (we never cancel on a network blip).
    # Best-effort: never raises to the caller. Called on card open and by the
    # periodic SyncSweepJob.
    class SyncService
      THROTTLE_TTL = 60.seconds

      pattr_initialize [:meeting!, [:force, false]]

      def perform
        return unless syncable?
        return if !force && Rails.cache.read(throttle_key).present?

        state = provider_event_state
        apply_state(state)
        # Arm the throttle only for a CONCLUSIVE live result so a transient failure
        # (:unknown) is retried sooner instead of being suppressed for 60s.
        Rails.cache.write(throttle_key, true, expires_in: THROTTLE_TTL) unless state[:status] == :unknown
      rescue StandardError => e
        Rails.logger.warn("CRM meeting sync failed (meeting #{meeting.id}): #{e.class.name}")
        nil
      end

      private

      def apply_state(state)
        case state[:status]
        when :deleted, :cancelled
          cancel_locally! if cancellable?
        when :active
          reschedule_locally!(state[:body]) if time_changed?(state[:body])
          RsvpSyncService.new(meeting: meeting).apply!(state[:body])
        end
      end

      # Same gate as RsvpSyncService: a real, non-simulated provider event.
      def syncable?
        return false if meeting.external_event_id.blank?
        return false if meeting.external_event_id.to_s.start_with?('sim-')

        case meeting.provider
        when 'google' then !Crm::Config.calendar_google_simulate?
        when 'microsoft' then !Crm::Config.calendar_ms_simulate?
        else false
        end
      end

      def throttle_key
        "crm_meeting_sync:#{meeting.id}"
      end

      def provider_event_state
        case meeting.provider
        when 'google'
          Google::CalendarEventService.new(channel: meeting.email_channel, meeting_params: {}, guests: [])
                                      .event_state(meeting.external_event_id)
        when 'microsoft'
          Microsoft::CalendarEventService.new(meeting: meeting).event_state(meeting.external_event_id)
        else
          { status: :unknown }
        end
      end

      def cancellable?
        meeting.scheduled? || meeting.rescheduled?
      end

      def cancel_locally!
        Crm::Meetings::CancelService.new(meeting: meeting, propagate: false).perform
      end

      def time_changed?(body)
        new_start, new_end = provider_times(body)
        return false if new_start.blank? || new_end.blank?
        return false if meeting.starts_at.blank? || meeting.ends_at.blank?

        # Compare at second resolution — providers don't carry sub-second precision,
        # so this avoids a spurious reschedule from microsecond/format differences.
        new_start.to_i != meeting.starts_at.to_i || new_end.to_i != meeting.ends_at.to_i
      end

      def reschedule_locally!(body)
        new_start, new_end = provider_times(body)
        Crm::Meetings::RescheduleService.new(
          meeting: meeting,
          propagate: false,
          params: { starts_at: new_start, ends_at: new_end, timezone: meeting.timezone }
        ).perform
      end

      def provider_times(body)
        meeting.microsoft? ? microsoft_times(body) : google_times(body)
      end

      # Google: start/end dateTime is RFC3339 with offset. All-day events carry only
      # 'date' (no time) — we skip those (return nils -> no reschedule).
      def google_times(body)
        [parse_iso(body.dig('start', 'dateTime')), parse_iso(body.dig('end', 'dateTime'))]
      end

      # Microsoft: naive dateTime paired with a timeZone field.
      def microsoft_times(body)
        [
          parse_ms(body.dig('start', 'dateTime'), body.dig('start', 'timeZone')),
          parse_ms(body.dig('end', 'dateTime'), body.dig('end', 'timeZone'))
        ]
      end

      def parse_iso(value)
        return if value.blank?

        Time.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def parse_ms(value, zone)
        return if value.blank?

        # We request Graph reads with Prefer: outlook.timezone="UTC", so zone is "UTC"
        # here. If it is ever an unresolvable Windows id, fall back to UTC (NOT the app
        # zone) to match that header — never silently shift the instant.
        tz = Time.find_zone(zone.to_s) || Time.find_zone('UTC')
        tz.parse(value.to_s)&.utc
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
