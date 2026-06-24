class Google::CalendarAccessTokenService < BaseRefreshOauthTokenService
  private

  # Builds the OAuth strategy for Google.
  # Credentials are resolved by channel account, with the global app as fallback.
  def build_oauth_strategy
    creds = ::EmailOauth::CredentialResolver.new(channel.account, 'google').credentials

    OmniAuth::Strategies::GoogleOauth2.new(nil, creds[:client_id], creds[:client_secret])
  end

  def update_channel_provider_config(new_tokens)
    channel.provider_config = {
      access_token: new_tokens[:access_token],
      refresh_token: new_tokens[:refresh_token].presence || provider_config[:refresh_token],
      expires_on: Time.at(new_tokens[:expires_at]).utc.to_s
    }
    channel.save!
  end
end
