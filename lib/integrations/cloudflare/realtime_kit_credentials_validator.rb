module Integrations::Cloudflare::RealtimeKitCredentialsValidator
  BASE_URL = 'https://api.cloudflare.com/client/v4'.freeze
  TIMEOUT_SECONDS = 5

  def self.valid?(account_id, app_id, api_token)
    return false if account_id.blank? || app_id.blank? || api_token.blank?

    token_active?(api_token) && realtimekit_app_exists?(account_id, app_id, api_token)
  rescue Faraday::Error => e
    Rails.logger.warn("[cloudflare-realtimekit-credentials-validator] #{e.class}: #{e.message}")
    true
  end

  def self.token_active?(api_token)
    response = connection.get("#{BASE_URL}/user/tokens/verify") do |req|
      req.headers['Authorization'] = "Bearer #{api_token}"
    end

    return true if transient_error?(response)

    body = parse_response(response)
    response.status == 200 && body['success'] == true && body.dig('result', 'status') == 'active'
  end
  private_class_method :token_active?

  def self.realtimekit_app_exists?(account_id, app_id, api_token)
    response = connection.get("#{BASE_URL}/accounts/#{account_id}/realtime/kit/apps") do |req|
      req.headers['Authorization'] = "Bearer #{api_token}"
    end

    return true if transient_error?(response)
    return false unless response.status == 200

    apps = parse_response(response)['data'] || []
    apps.any? { |app| app['id'] == app_id }
  end
  private_class_method :realtimekit_app_exists?

  def self.connection
    Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
    end
  end
  private_class_method :connection

  def self.parse_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError
    {}
  end
  private_class_method :parse_response

  def self.transient_error?(response)
    response.status >= 500
  end
  private_class_method :transient_error?
end
