class EmailCampaigns::ScheduleDueCampaignsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    EmailCampaigns::Scheduler.new.perform
  end
end
