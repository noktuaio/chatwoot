module GoogleConcern
  extend ActiveSupport::Concern

  def google_client
    creds = ::EmailOauth::CredentialResolver.new(oauth_account, 'google').credentials

    ::OAuth2::Client.new(creds[:client_id], creds[:client_secret], {
                           site: 'https://oauth2.googleapis.com',
                           authorize_url: 'https://accounts.google.com/o/oauth2/auth',
                           token_url: 'https://accounts.google.com/o/oauth2/token'
                         })
  end

  private

  def scope
    'email profile https://mail.google.com/'
  end
end
