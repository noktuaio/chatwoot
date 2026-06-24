module Crm
  module Calendar
    # Triggered by a provider push notification (S7-B): re-sync the upcoming
    # scheduled, real-provider meetings of ONE mailbox through SyncService (the same
    # authenticated reconciliation the pull sweep uses). force:true bypasses the 60s
    # throttle since a webhook is an authoritative "something changed now" signal.
    class WebhookSyncJob < ApplicationJob
      queue_as :scheduled_jobs

      # A small past window too, so a meeting that just ended and was canceled still
      # reconciles; a generous future window since webhooks are cheap (one mailbox).
      PAST_WINDOW = 1.day
      FUTURE_WINDOW = 60.days

      def perform(inbox_id)
        return unless Crm::Config.calendar_meetings_enabled?
        # Same kill-switch as the renewal job: turning webhooks OFF stops processing too
        # (not just subscription renewal), so safe-off/rollback is complete.
        return unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_CALENDAR_WEBHOOKS_ENABLED', false))
        return if inbox_id.blank?

        meetings_for(inbox_id).find_each do |meeting|
          Crm::Meetings::SyncService.new(meeting: meeting, force: true).perform
        end
      end

      private

      def meetings_for(inbox_id)
        Crm::Meeting
          .where(inbox_id: inbox_id, status: :scheduled)
          .where.not(external_event_id: nil)
          .where('external_event_id NOT LIKE ?', 'sim-%')
          .where('starts_at > ? AND starts_at < ?', Time.current - PAST_WINDOW, Time.current + FUTURE_WINDOW)
      end
    end
  end
end
