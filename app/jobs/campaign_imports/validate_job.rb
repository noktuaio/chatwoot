class CampaignImports::ValidateJob < ApplicationJob
  queue_as :low

  def perform(campaign_import)
    return unless CampaignImports::Config.enabled?

    CampaignImports::Validator.new(campaign_import).perform
  end
end
