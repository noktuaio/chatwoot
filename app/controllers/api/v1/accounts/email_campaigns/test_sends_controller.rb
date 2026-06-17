class Api::V1::Accounts::EmailCampaigns::TestSendsController < Api::V1::Accounts::EmailCampaigns::BaseController
  def create
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    authorize campaign, :update?

    to_email = params[:to_email].to_s.strip
    return render_unprocessable('email_campaign.invalid_email') unless Devise.email_regexp.match?(to_email)
    return render_unprocessable('email_campaign.sender_identity_missing') if campaign.sender_identity.blank?

    renderer = EmailCampaigns::TemplateRenderer.new(sample_recipient(campaign, to_email), inert_unsubscribe: true)
    message_id = EmailCampaigns::Ses::Sender.new(campaign.sender_identity).deliver(
      to: to_email,
      subject: renderer.render(campaign.subject),
      html_body: inject_preheader(renderer.render(campaign.body_html), renderer.render(campaign.preheader)),
      reply_to: campaign.reply_to.presence || campaign.sender_identity.from_email.presence,
      from_email: from_email(campaign)
    )
    render json: { message_id: message_id }
  rescue EmailCampaigns::Ses::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Render with the first real recipient (real custom_data drops) or a fake in-memory one.
  def sample_recipient(campaign, to_email)
    campaign.email_campaign_recipients.order(:id).first ||
      campaign.email_campaign_recipients.new(name: 'Contato Teste', email: to_email)
  end

  # Inject a hidden preheader snippet right after <body> (or at the top of the html) so the test
  # send mirrors the real send's inbox preview text. Text is rendered via TemplateRenderer.
  def inject_preheader(html, preheader)
    return html if preheader.blank?

    snippet = '<div style="display:none;visibility:hidden;max-height:0;overflow:hidden;mso-hide:all;' \
              "font-size:0;line-height:0;color:transparent;\">#{preheader}#{'&zwnj;&nbsp;' * 60}</div>"
    if html =~ /<body[^>]*>/i
      html.sub(/(<body[^>]*>)/i) { "#{Regexp.last_match(1)}#{snippet}" }
    else
      snippet + html
    end
  end

  def from_email(campaign)
    name = campaign.from_name.presence
    addr = campaign.from_email.presence || campaign.sender_identity.from_email.presence
    addr.present? && name.present? ? "#{name} <#{addr}>" : addr
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
