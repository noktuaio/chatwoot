class CampaignImports::UndoLabelsJob < ApplicationJob
  queue_as :low

  def perform(campaign_import)
    return unless CampaignImports::Config.enabled?

    CampaignImports::UndoLabels.new(campaign_import).perform
  end
end
