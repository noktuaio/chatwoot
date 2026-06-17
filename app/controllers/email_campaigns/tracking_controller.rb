class EmailCampaigns::TrackingController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :set_current_user, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  TRANSPARENT_GIF = "GIF89a\x01\x00\x01\x00\x80\x00\x00\xFF\xFF\xFF\x00\x00\x00!\xF9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b.freeze

  # GET /email_campaigns/t/o/:token (format gif) — open pixel. ALWAYS returns 200 + the GIF,
  # even on a bad token or disabled feature (never leak validity; never error a mail client).
  def open
    record_open if EmailCampaigns::Config.enabled?
    send_pixel
  end

  # GET /email_campaigns/t/c/:token — click redirect. Verify token, record, 302 to the SIGNED
  # original URL ONLY. On bad token → redirect to the tracking base (never open-redirect, never
  # echo an attacker URL).
  def click
    data = EmailCampaigns::Tracking::Token.decode_click(params[:token]) if EmailCampaigns::Config.enabled?
    url = safe_redirect_url(data)
    record_click(data, url) if EmailCampaigns::Config.enabled? && data.present?
    redirect_to url, allow_other_host: true
  end

  private

  def record_open
    data = EmailCampaigns::Tracking::Token.decode_open(params[:token])
    return if data.blank?

    recipient = EmailCampaignRecipient.find_by(id: data[:r] || data['r'])
    return if recipient.nil?

    EmailCampaigns::Tracking::EventRecorder.new(recipient).record_open('ua' => request.user_agent)
  rescue StandardError => e
    Rails.logger.warn("[EmailCampaigns::Tracking#open] #{e.message}")
  end

  def record_click(data, url)
    recipient = EmailCampaignRecipient.find_by(id: data[:r] || data['r'])
    return if recipient.nil?

    EmailCampaigns::Tracking::EventRecorder.new(recipient).record_click(url, 'ua' => request.user_agent)
  rescue StandardError => e
    Rails.logger.warn("[EmailCampaigns::Tracking#click] #{e.message}")
  end

  # ONLY the signed url from a valid token; otherwise the tracking base. Never an open redirect.
  def safe_redirect_url(data)
    candidate = (data && (data[:u] || data['u'])).to_s
    return EmailCampaigns::Tracking::Token.base_url unless candidate =~ %r{\Ahttps?://}i

    candidate
  end

  def send_pixel
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
    send_data TRANSPARENT_GIF, type: 'image/gif', disposition: 'inline'
  end
end
