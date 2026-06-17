class Crm::FollowUpDueJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless Crm::Config.enabled?

    Crm::FollowUps::DueProcessor.new.perform
  end
end
