module WhatsappApiCampaigns
  class Scheduler
    def perform
      return unless Config.enabled?

      WhatsappApiCampaign.scheduled.where('scheduled_at <= ?', Time.current).find_each(batch_size: 50) do |campaign|
        start_campaign(campaign)
      end
    end

    private

    def start_campaign(campaign)
      should_enqueue = false
      campaign.with_lock do
        campaign.reload
        next unless campaign.scheduled?
        next unless campaign.scheduled_at <= Time.current
        next unless campaign.inbox.api? && campaign.inbox.channel.whatsapp_api_campaign_channel?

        AudienceResolver.new(campaign).perform
        if campaign.whatsapp_api_campaign_recipients.pending.exists?
          campaign.update!(status: :running, started_at: Time.current)
          should_enqueue = true
        elsif campaign.whatsapp_api_campaign_recipients.failed.exists?
          campaign.update!(status: :completed_with_failures, completed_at: Time.current)
        else
          campaign.update!(status: :completed, completed_at: Time.current)
        end
      end

      DeliveryJob.perform_later(campaign.id) if should_enqueue && Config.enabled?
    rescue StandardError => e
      campaign.update!(status: :failed, last_error_message: e.message.to_s.truncate(500)) if campaign&.persisted?
    end
  end
end
