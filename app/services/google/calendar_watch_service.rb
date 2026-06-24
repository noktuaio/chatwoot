require 'net/http'

# Manages a Google Calendar push-notification channel (S7-B) on a mailbox's primary
# calendar events. Google does not renew channels — they are re-created before expiry
# (handled by the SubscriptionManager). Auth reuses Google::CalendarAccessTokenService,
# the same path as the other calendar services.
class Google::CalendarWatchService
  pattr_initialize [:channel!]

  CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'.freeze

  # Start a watch channel. channel_id is a UUID we generate; address is our public
  # webhook URL; token is the shared secret echoed back as X-Goog-Channel-Token.
  # Returns { resource_id:, expiration_ms: } on success, raises on failure.
  def watch(channel_id:, address:, token:, ttl_seconds: nil)
    payload = { id: channel_id, type: 'web_hook', address: address, token: token }
    payload[:params] = { ttl: ttl_seconds.to_s } if ttl_seconds.present?

    response = post_json("#{CALENDAR_API_BASE}/calendars/primary/events/watch", payload)
    raise Google::CalendarError, "Google watch failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

    body = parse(response)
    { resource_id: body['resourceId'], expiration_ms: body['expiration'].to_i }
  end

  # Stop a channel. 200/204/404 are all success (already gone).
  def stop(channel_id:, resource_id:)
    return true if channel_id.blank? || resource_id.blank?

    response = post_json("#{CALENDAR_API_BASE}/channels/stop", { id: channel_id, resourceId: resource_id })
    [200, 204, 404].include?(response.code.to_i)
  end

  private

  def post_json(url, payload)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json
    http.request(request)
  end

  def access_token
    Google::CalendarAccessTokenService.new(channel: channel).access_token
  end

  def parse(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    {}
  end
end
