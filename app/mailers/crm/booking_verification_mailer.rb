# Sends the public-booking email-verification link. The meeting is created ONLY
# after the booker opens this link (proving control of the email), so this mailer
# is the security gate of slice S6's anti-abuse flow. It inherits ActionMailer::Base
# directly (not ApplicationMailer) because the public flow has no Current.account /
# Pundit context and the email is deliberately branded-neutral with an inline body
# (no DB/account-specific templates, no PII beyond the booker's own name/email).
class Crm::BookingVerificationMailer < ActionMailer::Base
  default from: ENV.fetch('MAILER_SENDER_EMAIL', 'Chatwoot <accounts@chatwoot.com>')

  def verify(email:, name:, agent_name:, confirm_url:, starts_at_label:)
    return unless smtp_config_set_or_development?

    @name = name.presence || email
    @agent_name = agent_name
    @confirm_url = confirm_url
    @starts_at_label = starts_at_label

    mail(to: email, subject: I18n.t('crm.booking.verification.subject', default: 'Confirme seu agendamento')) do |format|
      format.text { render plain: text_body }
      format.html { render html: html_body.html_safe }
    end
  end

  private

  def text_body
    [
      "Olá #{@name},",
      '',
      "Você solicitou uma reunião com #{@agent_name} em #{@starts_at_label}.",
      'Para confirmar o agendamento, abra o link abaixo:',
      @confirm_url,
      '',
      'Este link é válido por 30 minutos. Se você não solicitou este agendamento, ignore este e-mail.'
    ].join("\n")
  end

  # Minimal, inline, escaped HTML. Only @confirm_url is interpolated into an href,
  # and it is a server-built URL (FRONTEND_URL + slug + CGI-escaped token), so it is
  # not attacker-controlled; the booker-supplied name/agent_name are HTML-escaped.
  def html_body
    name = ERB::Util.html_escape(@name)
    agent = ERB::Util.html_escape(@agent_name)
    when_label = ERB::Util.html_escape(@starts_at_label)
    url = ERB::Util.html_escape(@confirm_url)

    <<~HTML
      <p>Olá #{name},</p>
      <p>Você solicitou uma reunião com <strong>#{agent}</strong> em <strong>#{when_label}</strong>.</p>
      <p><a href="#{url}">Confirmar agendamento</a></p>
      <p style="color:#64748b;font-size:13px;">Este link é válido por 30 minutos. Se você não solicitou este agendamento, ignore este e-mail.</p>
    HTML
  end

  def smtp_config_set_or_development?
    ENV.fetch('SMTP_ADDRESS', nil).present? || Rails.env.development?
  end
end
