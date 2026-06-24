module EmailCampaigns
  # Re-enqueues DeliveryJob for campaigns still in `sending` that have retryable pending
  # recipients (attempts < MAX_ATTEMPTS) whose last attempt is older than the backoff window.
  # Never touches sent/delivered recipients (only pending). DeliveryEngine is idempotent +
  # claim-guarded, so re-enqueue is safe (no double-send). Guarded by Config.enabled?.
  class RetrySweeper
    # Don't requeue a campaign whose recipients were just attempted; let SES settle.
    BACKOFF = (ENV.fetch('EMAIL_CAMPAIGN_RETRY_BACKOFF_MINUTES', 5).to_i).minutes

    def perform
      return unless Config.enabled?

      campaigns.find_each(batch_size: 50) { |campaign| requeue(campaign) }
    end

    private

    # sending campaigns that still have a retryable pending recipient past the backoff window.
    def campaigns
      EmailCampaign.where(status: EmailCampaign.statuses[:sending])
                   .where(id: retryable_campaign_ids)
                   .distinct
    end

    def retryable_campaign_ids
      EmailCampaignRecipient
        .where(status: EmailCampaignRecipient.statuses[:pending])
        .where('attempts < ?', EmailCampaignRecipient::MAX_ATTEMPTS)
        .where('attempts > 0')
        .where('updated_at <= ?', Time.current - BACKOFF)
        .select(:email_campaign_id)
    end

    def requeue(campaign)
      EmailCampaigns::DeliveryJob.perform_later(campaign.id)
    rescue StandardError => e
      Rails.logger.error("[EmailCampaigns::RetrySweeper] campaign=#{campaign.id} #{e.message}")
    end
  end
end
