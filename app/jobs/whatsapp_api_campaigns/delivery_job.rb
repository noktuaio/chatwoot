class WhatsappApiCampaigns::DeliveryJob < ApplicationJob
  queue_as :low

  def perform(campaign_id)
    return unless WhatsappApiCampaigns::Config.enabled?

    campaign = WhatsappApiCampaign.find_by(id: campaign_id)
    return if campaign.blank?

    WhatsappApiCampaigns::DeliveryEngine.new(campaign).perform
  end
end
