class EmailCampaigns::DomainVerificationPollJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(identity_id)
    return unless EmailCampaigns::Config.enabled?

    identity = EmailSenderIdentity.find_by(id: identity_id)
    return if identity.nil? || identity.verified?

    response = EmailCampaigns::Ses::Client.new.get_email_identity(identity.domain)
    verified = response['VerifiedForSendingStatus'] == true ||
               response.dig('DkimAttributes', 'Status') == 'SUCCESS'
    if verified
      identity.update!(status: :verified, verified_at: Time.current, last_error: nil)
    else
      identity.update!(status: :verifying, last_error: nil)
    end
  rescue EmailCampaigns::Ses::Error => e
    return if identity.nil?

    unless identity.update(status: :failed, last_error: e.message.to_s.truncate(255))
      Rails.logger.error(
        "[EmailCampaigns] failed to persist verification failure for identity #{identity.id}: " \
        "#{identity.errors.full_messages.join(', ')}"
      )
    end
  end
end
