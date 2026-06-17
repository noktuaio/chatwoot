class EmailCampaigns::RetrySweepJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    EmailCampaigns::RetrySweeper.new.perform
  end
end
