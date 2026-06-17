class EmailCampaigns::PollPendingIdentitiesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    EmailSenderIdentity.pending_verification.find_each do |identity|
      EmailCampaigns::DomainVerificationPollJob.perform_later(identity.id)
    end
  end
end
