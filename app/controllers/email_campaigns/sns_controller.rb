class EmailCampaigns::SnsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :set_current_user, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  # POST /email_campaigns/sns  — SES event notifications via SNS (Delivery/Bounce/Complaint).
  # Handles SubscriptionConfirmation (auto-confirm) + Notification. Verifies the SNS signature.
  def create
    return head :not_found unless EmailCampaigns::Config.enabled?

    raw = request.raw_post
    EmailCampaigns::Sns::MessageHandler.new(raw).process
    head :ok
  rescue EmailCampaigns::Sns::MessageHandler::InvalidSignature
    head :forbidden
  rescue StandardError => e
    Rails.logger.error("[EmailCampaigns::Sns] #{e.message}")
    head :ok # 200 so SNS does not hot-retry on our internal error; we log + drop.
  end
end
