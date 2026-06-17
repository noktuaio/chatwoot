class EmailCampaigns::GuardrailSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    account_ids = EmailCampaignRecipient.joins(:email_campaign)
                                        .where(sent_at: EmailCampaigns::Guardrail::WINDOW.ago..)
                                        .distinct
                                        .pluck('email_campaigns.account_id')
    Account.where(id: account_ids).find_each { |account| EmailCampaigns::Guardrail.evaluate!(account) }
  end
end
