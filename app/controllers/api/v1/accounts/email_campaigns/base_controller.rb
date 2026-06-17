class Api::V1::Accounts::EmailCampaigns::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_email_campaign_enabled

  private

  def ensure_email_campaign_enabled
    return if ::EmailCampaigns::Config.enabled?

    render json: { error: 'email_campaign.disabled' }, status: :not_found
  end
end
