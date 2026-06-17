class CampaignImports::ImportJob < ApplicationJob
  queue_as :low

  def perform(campaign_import)
    return unless CampaignImports::Config.enabled?

    CampaignImports::Importer.new(campaign_import).perform
  end
end
