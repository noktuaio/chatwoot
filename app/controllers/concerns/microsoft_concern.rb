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
    # (substitui o SMTP.Send, imune ao Security Defaults).
    [
      'offline_access',
      'https://outlook.office.com/IMAP.AccessAsUser.All',
      'https://graph.microsoft.com/Mail.Send',
      'https://graph.microsoft.com/Mail.ReadWrite',
      'openid profile email'
    ].join(' ')
  end
end
