# frozen_string_literal: true

require 'base64'
require 'digest'

class Autonomia::AuthController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def start
    return redirect_to login_page_url(error: 'autonomia-sso-disabled') unless sso_enabled?

    state = SecureRandom.urlsafe_base64(32)
    verifier = SecureRandom.urlsafe_base64(64)
    session[:autonomia_sso] = {
      state: state,
      code_verifier: verifier,
      return_to: permitted_return_to
    }

    redirect_to authorization_url(state, verifier), allow_other_host: true
  end

  def callback
    return redirect_to login_page_url(error: 'autonomia-sso-error') if params[:error].present?
    return redirect_to login_page_url(error: 'autonomia-sso-state') unless valid_state?

    token = Autonomia::Sso::Client.new.exchange_code!(
      code: params.require(:code),
      redirect_uri: callback_url,
      code_verifier: sso_session[:code_verifier]
    )
    context = Autonomia::Sso::Client.new.fetch_context!(token.access_token)
    user = Autonomia::Sso::Provisioner.new(context: context).perform

    session.delete(:autonomia_sso)
    redirect_to login_page_url(email: ERB::Util.url_encode(user.email), sso_auth_token: user.generate_sso_auth_token)
  rescue StandardError => e
    Rails.logger.error("[Autonomia SSO] #{e.class}: #{e.message}")
    redirect_to login_page_url(error: 'autonomia-sso-error')
  end

  private

  def authorization_url(state, verifier)
    uri = URI.join(issuer_url, '/login')
    uri.query = {
      client_id: client_id,
      redirect_uri: callback_url,
      response_type: 'code',
      scope: 'openid email profile',
      state: state,
      code_challenge: pkce_challenge(verifier),
      code_challenge_method: 'S256',
      return_to: permitted_return_to
    }.compact.to_query
    uri.to_s
  end

  def valid_state?
    expected_state = sso_session[:state].to_s
    actual_state = params[:state].to_s
    expected_state.present? && expected_state.bytesize == actual_state.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(expected_state, actual_state)
  end

  def pkce_challenge(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  end

  def sso_session
    session[:autonomia_sso] || {}
  end

  def callback_url
    ENV.fetch('AUTONOMIA_AUTH_REDIRECT_URI', "#{frontend_url}/auth/autonomia/callback")
  end

  def permitted_return_to
    return nil if params[:return_to].blank?

    value = params[:return_to].to_s
    value.start_with?('/app') ? value : nil
  end

  def login_page_url(error: nil, email: nil, sso_auth_token: nil)
    query = { email: email, sso_auth_token: sso_auth_token }.compact
    query[:error] = error if error.present?
    "#{frontend_url}/app/login?#{query.to_query}"
  end

  def frontend_url
    ENV.fetch('FRONTEND_URL', request.base_url)
  end

  def issuer_url
    ENV.fetch('AUTONOMIA_AUTH_ISSUER', 'https://auth.autonomia.site').delete_suffix('/')
  end

  def client_id
    ENV.fetch('AUTONOMIA_AUTH_CLIENT_ID', 'talkai')
  end

  def sso_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('AUTONOMIA_SSO_ENABLED', true))
  end
end
