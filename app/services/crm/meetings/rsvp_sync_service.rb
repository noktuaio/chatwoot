module Crm
  module Meetings
    # Best-effort refresh of each guest's RSVP status from the provider's calendar
    # (Google Calendar or Microsoft Graph). Called when a meeting detail opens (and
    # on manual refresh). Never raises to the controller — any failure is logged and
    # swallowed.
    class RsvpSyncService
      THROTTLE_TTL = 60.seconds

      # Google Calendar attendee.responseStatus -> rsvp enum.
      RESPONSE_STATUS_MAP = {
        'accepted' => :rsvp_accepted,
        'declined' => :rsvp_declined,
        'tentative' => :rsvp_tentative
      }.freeze

      # Microsoft Graph attendee.status.response -> rsvp enum.
      MS_RESPONSE_STATUS_MAP = {
        'accepted' => :rsvp_accepted,
        'declined' => :rsvp_declined,
        'tentativelyAccepted' => :rsvp_tentative
      }.freeze

      pattr_initialize [:meeting!, [:force, false]]

      def perform
        return unless syncable?
        return if !force && Rails.cache.read(throttle_key).present?

        body = fetch_event
        apply_rsvp(body) if body.present?
        # Arm the throttle for any completed live attempt — including a deleted/blank
        # event (non-2xx) — so we don't re-hit Google on every card open. A raised
        # transient error skips this (rescue below) so it can retry sooner.
        Rails.cache.write(throttle_key, true, expires_in: THROTTLE_TTL)
      rescue StandardError => e
        Rails.logger.warn("CRM meeting RSVP sync failed (meeting #{meeting.id}): #{e.class.name}")
        nil
      end

      # Apply RSVP from an ALREADY-fetched provider event body (S7 SyncService fetches
      # the event once via event_state and hands the body here, avoiding a second GET).
      def apply!(body)
        apply_rsvp(body) if body.present?
      rescue StandardError => e
        Rails.logger.warn("CRM meeting RSVP apply failed (meeting #{meeting.id}): #{e.class.name}")
        nil
      end

      private

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
        "crm_meeting_rsvp_sync:#{meeting.id}"
      end

      # Reads the event back from the provider, mirroring the create path. Returns the
      # parsed event body (or nil). Google and Microsoft return different shapes —
      # normalized in attendee_statuses.
      def fetch_event
        case meeting.provider
        when 'google'
          Google::CalendarEventService.new(
            channel: meeting.email_channel,
            meeting_params: {},
            guests: []
          ).fetch_event(meeting.external_event_id)
        when 'microsoft'
          Microsoft::CalendarEventService.new(meeting: meeting).fetch_event(meeting.external_event_id)
        end
      end

      def apply_rsvp(body)
        statuses = attendee_statuses(body)
        meeting.meeting_guests.each do |guest|
          new_status = statuses[guest.email.to_s.downcase]
          next if new_status.blank?
          next if guest.rsvp_status == new_status.to_s

          guest.update!(rsvp_status: new_status)
        end
      end

      def attendee_statuses(body)
        meeting.provider == 'microsoft' ? microsoft_attendee_statuses(body) : google_attendee_statuses(body)
      end

      def google_attendee_statuses(body)
        Array(body['attendees']).each_with_object({}) do |attendee, acc|
          email = attendee['email'].to_s.downcase
          next if email.blank?

          acc[email] = RESPONSE_STATUS_MAP.fetch(attendee['responseStatus'], :rsvp_pending)
        end
      end

      def microsoft_attendee_statuses(body)
        Array(body['attendees']).each_with_object({}) do |attendee, acc|
          email = attendee.dig('emailAddress', 'address').to_s.downcase
          next if email.blank?

          acc[email] = MS_RESPONSE_STATUS_MAP.fetch(attendee.dig('status', 'response'), :rsvp_pending)
        end
      end
    end
  end
end
