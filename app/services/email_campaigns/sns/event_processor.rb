module EmailCampaigns
  module Sns
    # Maps an SES event JSON (Delivery/Bounce/Complaint) keyed by mail.messageId to the
    # EmailCampaignRecipient (by ses_message_id), records an EmailEvent, advances the recipient
    # status + campaign counters, and auto-suppresses (account-scoped, idempotent) on hard
    # bounce / complaint. Defensive: returns nil on unknown recipient / event type.
    class EventProcessor
      def initialize(ses_event)
        @event = ses_event || {}
      end

      def process
        recipient = find_recipient
        return if recipient.nil?

        case event_type
        when 'Delivery'  then on_delivery(recipient)
        when 'Bounce'    then on_bounce(recipient)
        when 'Complaint' then on_complaint(recipient)
        end
      end

      private

      # SES publishes either eventType (event publishing) or notificationType (legacy feedback).
      def event_type
        @event['eventType'] || @event['notificationType']
      end

      def message_id
        @event.dig('mail', 'messageId')
      end

      def find_recipient
        return nil if message_id.blank?

        EmailCampaignRecipient.find_by(ses_message_id: message_id)
      end

      def campaign_for(recipient)
        recipient.email_campaign
      end

      # SNS guarantees AT-LEAST-ONCE delivery and routinely redelivers the same notification.
      # These SES event types are once-per-recipient, so guard on existence before create!
      # (mirrors EventRecorder#record_open) to keep refresh_counters! honest under redelivery.
      def on_delivery(recipient)
        return if recipient.email_events.where(event_type: :delivered).exists?

        recipient.email_events.create!(event_type: :delivered, occurred_at: Time.current, payload: @event)
        recipient.mark_delivered!
        campaign_for(recipient).refresh_counters!
      end

      def on_bounce(recipient)
        return if recipient.email_events.where(event_type: :bounce).exists?

        recipient.email_events.create!(event_type: :bounce, occurred_at: Time.current, payload: @event)
        recipient.mark_bounced!
        campaign = campaign_for(recipient)
        campaign.refresh_counters!
        suppress!(campaign.account, recipient.email, 'hard_bounce') if permanent_bounce?
      end

      def on_complaint(recipient)
        return if recipient.email_events.where(event_type: :complaint).exists?

        recipient.email_events.create!(event_type: :complaint, occurred_at: Time.current, payload: @event)
        recipient.mark_complained!
        campaign = campaign_for(recipient)
        campaign.refresh_counters!
        suppress!(campaign.account, recipient.email, 'complaint')
      end

      def permanent_bounce?
        @event.dig('bounce', 'bounceType') == 'Permanent'
      end

      # Account-scoped, idempotent (unique index on account_id + lower(email)).
      def suppress!(account, email, reason)
        EmailSuppression.create!(account: account, email: email, reason: reason, source: 'ses')
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        nil
      end
    end
  end
end
