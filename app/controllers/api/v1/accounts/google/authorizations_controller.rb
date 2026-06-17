class Api::V1::Accounts::Google::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include GoogleConcern

  def create
    redirect_url = google_client.auth_code.authorize_url(
      {
        redirect_uri: "#{base_url}/google/callback",
        scope: scope,
        response_type: 'code',
        prompt: 'consent', # the oauth flow does not return a refresh token, this is supposed to fix it
        access_type: 'offline', # the default is 'online'
        state: state
        # client_id vem do google_client (resolvido por conta, com fallback global) —
        # não forçar o global aqui, senão a conta com app próprio quebra no callback.
      }
    )

    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end
end
