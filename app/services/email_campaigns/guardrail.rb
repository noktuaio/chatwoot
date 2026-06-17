module EmailCampaigns
  # Per-tenant deliverability guardrail (Onda D). Evaluates the trailing 7-day window and
  # pauses the tenant's email campaigns when bounce rate > 5% OR complaint rate > 0.3%
  # (minimum 50 sends to evaluate). The flag lives in account.internal_attributes so the
  # DeliveryEngine and the sweep job share a single source of truth.
  class Guardrail
    WINDOW = 7.days
    MIN_SENDS = 50
    BOUNCE_RATE_LIMIT = 0.05
    COMPLAINT_RATE_LIMIT = 0.003
    FLAG_KEY = 'email_campaigns_paused'.freeze

    class << self
      # Evaluates the window and pauses the tenant when over the limits. Returns true when paused.
      def evaluate!(account)
        return true if paused?(account)

        sends = sends_in_window(account)
        return false if sends < MIN_SENDS

        bounce_rate = events_in_window(account, :bounce) / sends.to_f
        complaint_rate = events_in_window(account, :complaint) / sends.to_f
        return false unless bounce_rate > BOUNCE_RATE_LIMIT || complaint_rate > COMPLAINT_RATE_LIMIT

        pause!(account, reason(sends, bounce_rate, complaint_rate))
        true
      end

      def paused?(account)
        account.internal_attributes[FLAG_KEY].present?
      end

      def resume!(account)
        account.internal_attributes.delete(FLAG_KEY)
        account.save!
      end

      private

      def pause!(account, reason)
        account.internal_attributes[FLAG_KEY] = { 'at' => Time.current.iso8601, 'reason' => reason }
        account.save!
      end

      def reason(sends, bounce_rate, complaint_rate)
        format('bounce_rate=%<bounce>.2f%% complaint_rate=%<complaint>.3f%% sends=%<sends>d (janela 7d; limites: bounce > 5%%, complaint > 0.3%%)',
               bounce: bounce_rate * 100, complaint: complaint_rate * 100, sends: sends)
      end

      def sends_in_window(account)
        EmailCampaignRecipient.joins(:email_campaign)
                              .where(email_campaigns: { account_id: account.id })
                              .where(sent_at: WINDOW.ago..)
                              .count
      end

      def events_in_window(account, type)
        EmailEvent.joins(recipient: :email_campaign)
                  .where(email_campaigns: { account_id: account.id })
                  .where(event_type: EmailEvent.event_types[type])
                  .where(occurred_at: WINDOW.ago..)
                  .count
      end
    end
  end
end
