class WhatsappApiCampaigns::ScheduleDueCampaignsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless WhatsappApiCampaigns::Config.enabled?

    WhatsappApiCampaigns::Scheduler.new.perform
  end
end
