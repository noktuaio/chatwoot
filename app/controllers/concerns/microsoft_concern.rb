module MicrosoftConcern
  extend ActiveSupport::Concern

  def microsoft_client
    creds = ::EmailOauth::CredentialResolver.new(oauth_account, 'microsoft').credentials

    ::OAuth2::Client.new(creds[:client_id], creds[:client_secret],
                         {
                           site: 'https://login.microsoftonline.com',
                           authorize_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
                           token_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
                         })
  end

  private

  def scope
    # IMAP.AccessAsUser.All: entrada (IMAP). Graph Mail.Send/ReadWrite: saída via Graph
    # (substitui o SMTP.Send, imune ao Security Defaults). Calendars.ReadWrite só é
    # somado quando a feature de reuniões está ligada (agenda = capacidade da caixa),
    # mantendo SEMPRE o escopo de e-mail completo (IMAP + openid) no consentimento.
    parts = [
      'offline_access',
      'https://outlook.office.com/IMAP.AccessAsUser.All',
      'https://graph.microsoft.com/Mail.Send',
      'https://graph.microsoft.com/Mail.ReadWrite',
      'openid profile email'
    ]
    parts << 'https://graph.microsoft.com/Calendars.ReadWrite' if request_calendar_scope?
    parts.join(' ')
  end

  def request_calendar_scope?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_CALENDAR_MEETINGS_ENABLED', false)) || calendar_oauth_intent?
  end

  def calendar_oauth_intent?
    state_params = (session[:oauth_state_params] || {}).with_indifferent_access

    params[:calendar_intent].present? ||
      params[:intent].to_s == 'calendar' ||
      params[:oauth_intent].to_s == 'calendar' ||
      state_params[:calendar_intent].present? ||
      state_params[:intent].to_s == 'calendar' ||
      state_params[:oauth_intent].to_s == 'calendar'
  end
end
