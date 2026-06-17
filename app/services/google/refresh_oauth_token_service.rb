# Refer: https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes
class Google::RefreshOauthTokenService < BaseRefreshOauthTokenService
  private

  # Builds the OAuth strategy for Google.
  # Credenciais resolvidas pela CONTA do canal (com fallback global).
  def build_oauth_strategy
    creds = ::EmailOauth::CredentialResolver.new(channel.account, 'google').credentials

    OmniAuth::Strategies::GoogleOauth2.new(nil, creds[:client_id], creds[:client_secret])
  end
end
