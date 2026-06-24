class EmailCampaigns::DeliveryJob < ApplicationJob
  queue_as :low

  def perform(campaign_id)
    return unless EmailCampaigns::Config.enabled?

    campaign = EmailCampaign.find_by(id: campaign_id)
    return if campaign.blank?

    # Modo direto (caixa webmail) tem motor próprio com throttle; SES segue o engine de sempre.
    if campaign.direct_inbox?
      EmailCampaigns::DirectInbox::TickJob.perform_later(campaign.id)
    else
      EmailCampaigns::DeliveryEngine.new(campaign).perform
    end
  end
end
