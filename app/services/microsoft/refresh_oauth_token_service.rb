# Refer: https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes
class Microsoft::RefreshOauthTokenService < BaseRefreshOauthTokenService
  private

  # Builds the OAuth strategy for Microsoft Graph.
  # Credenciais resolvidas pela CONTA do canal (com fallback global).
  def build_oauth_strategy
    creds = ::EmailOauth::CredentialResolver.new(channel.account, 'microsoft').credentials
    ::MicrosoftGraphAuth.new(nil, creds[:client_id], creds[:client_secret])
  end

  # Token IMAP é do recurso Outlook — fixa o escopo no refresh (Azure v2 multi-recurso).
  def refresh_params
    { scope: ::Microsoft::Scopes::IMAP }
  end
end
