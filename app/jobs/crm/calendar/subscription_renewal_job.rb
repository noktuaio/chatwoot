module Crm
  module Calendar
    # Keeps push-notification subscriptions alive (S7-B). Runs periodically and, for
    # every real calendar mailbox, (re-)creates/renews the watch/subscription before
    # it expires (SubscriptionManager is idempotent + skips fresh ones).
    #
    # Gated OFF by default via CRM_CALENDAR_WEBHOOKS_ENABLED: creating a Google watch
    # channel requires the webhook DOMAIN to be verified in the Google Cloud Console
    # project, which is a manual prerequisite — so webhooks stay inert until both the
    # ENV flag is on AND that verification is done. The pull sweep (S7-A) covers sync
    # meanwhile.
    class SubscriptionRenewalJob < ApplicationJob
      queue_as :scheduled_jobs

      def perform
        return unless Crm::Config.calendar_meetings_enabled?
        return unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_CALENDAR_WEBHOOKS_ENABLED', false))

        calendar_inboxes.find_each do |inbox|
          Crm::Calendar::SubscriptionManager.ensure_for(inbox)
        end
      end

      private

      def calendar_inboxes
        Inbox.where(channel_type: 'Channel::Email',
                    channel_id: Channel::Email.where(calendar_enabled: true).select(:id))
      end
    end
  end
end
