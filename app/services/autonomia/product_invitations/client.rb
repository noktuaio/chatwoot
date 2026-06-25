# frozen_string_literal: true

require 'net/http'
require 'uri'

class Autonomia::ProductInvitations::Client
  class Error < StandardError; end

  def create!(authorization_token:, payload:)
    uri = URI.parse(endpoint)
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{authorization_token}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
    body = JSON.parse(response.body.presence || '{}')
    return body if response.is_a?(Net::HTTPSuccess)
    return email_delivery_fallback(body) if recoverable_invitation?(body)

    raise Error, error_message(body)
  rescue JSON::ParserError
    raise Error, 'Resposta invalida do Auth ao criar convite.'
  end

  private

  def endpoint
    ENV.fetch('AUTONOMIA_PRODUCT_INVITATIONS_ENDPOINT', 'https://auth.api-autonomia.com/auth/product-invitations')
  end

  def email_delivery_fallback(body)
    body.merge(
      'emailDeliveryFailed' => true,
      'manualShareRequired' => true,
      'emailDeliveryError' => error_message(body)
    )
  end

  def invitation_url(body)
    return if body.blank?

    body.dig('invitation', 'invitationUrl') ||
      body.dig('invitation', 'invitation_url') ||
      body['invitationUrl'] ||
      body['invitation_url']
  end

  def recoverable_invitation?(body)
    invitation_url(body).present? ||
      body['token'].present? ||
      body.dig('invitation', 'token').present?
  end

  def error_message(body)
    error = body['error']
    return error['message'] if error.is_a?(Hash) && error['message'].present?

    body['message'] || error || 'Nao foi possivel criar o convite no Auth.'
  end
end
