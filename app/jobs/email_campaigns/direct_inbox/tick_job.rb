class EmailCampaigns::DirectInbox::TickJob < ApplicationJob
  queue_as :low

  # Um "tick" = envia 1 destinatário e reagenda o próximo (o throttle vive no engine).
  def perform(campaign_id)
    return unless EmailCampaigns::Config.enabled?

    campaign = EmailCampaign.find_by(id: campaign_id)
    return if campaign.blank? || !campaign.direct_inbox?

    campaign.reload
    return unless campaign.sending? || campaign.scheduled?

    campaign.mark_sending! unless campaign.sending?
    EmailCampaigns::DirectInbox::DeliveryEngine.new(campaign).tick
  end
end
