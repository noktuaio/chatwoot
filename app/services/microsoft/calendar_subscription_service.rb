require 'net/http'

# Manages a Microsoft Graph change-notification subscription (S7-B) on a mailbox's
# events. MS subscriptions for /me/events expire fast (max ~70h) and ARE renewable
# via PATCH (the SubscriptionManager renews before expiry). Auth reuses
# Microsoft::GraphTokenService, the same path as the other calendar services.
class Microsoft::CalendarSubscriptionService
  pattr_initialize [:channel!]

  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze

  # Create a subscription. notification_url is our public webhook URL; client_state
  # is the shared secret Graph echoes back in every notification (we verify it).
  # Graph POSTs a validation handshake to notification_url first; our endpoint must
  # echo the validationToken (handled in the webhook controller).
  # Returns { subscription_id:, expiration: } on success, raises on failure.
  def create(notification_url:, client_state:, expiration:)
    payload = {
      changeType: 'updated,deleted',
      notificationUrl: notification_url,
      resource: '/me/events',
      expirationDateTime: expiration.utc.iso8601,
      clientState: client_state
    }
    response = request(:post, "#{GRAPH_API_BASE}/subscriptions", payload)
    raise Microsoft::CalendarError, "Graph subscribe failed (#{response.code})" unless [200, 201].include?(response.code.to_i)

    body = parse(response)
    { subscription_id: body['id'], expiration: body['expirationDateTime'] }
  end

  def renew(subscription_id:, expiration:)
    return false if subscription_id.blank?

    response = request(:patch, "#{GRAPH_API_BASE}/subscriptions/#{subscription_id}", { expirationDateTime: expiration.utc.iso8601 })
    response.code.to_i == 200
  end

  def delete(subscription_id:)
    return true if subscription_id.blank?

    response = request(:delete, "#{GRAPH_API_BASE}/subscriptions/#{subscription_id}", nil)
    [200, 204, 404].include?(response.code.to_i)
  end

  private

  def request(method, url, payload)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = build_request(method, uri)
    request['Authorization'] = "Bearer #{access_token}"
    if payload
      request['Content-Type'] = 'application/json'
      request.body = payload.to_json
    end
    http.request(request)
  end

  def build_request(method, uri)
    case method
    when :post then Net::HTTP::Post.new(uri)
    when :patch then Net::HTTP::Patch.new(uri)
    when :delete then Net::HTTP::Delete.new(uri)
    end
  end

  def access_token
    Microsoft::GraphTokenService.new(channel: channel).access_token
  end

  def parse(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    {}
  end
end
