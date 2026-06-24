require 'net/http'

# Reads the connected Google calendar's busy intervals for a time window via the
# /freeBusy endpoint. Channel-keyed (reuses Google::CalendarAccessTokenService for
# auth, the same path CalendarEventService uses). Best-effort: returns [] on any
# non-2xx response so availability never breaks scheduling.
class Google::FreeBusyService
  pattr_initialize [:channel!, :time_min!, :time_max!]

  CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'.freeze

  # Raised only when raise_on_error:true so a caller that must fail CLOSED (the
  # public-booking slot re-check) can reject instead of treating a provider
  # outage as "no busy intervals".
  class Error < StandardError; end

  # Returns an array of { start: Time, end: Time } busy blocks.
  # raise_on_error:false (default) — best-effort: [] on any non-2xx (display path).
  # raise_on_error:true — fail-closed: a non-2xx response raises so booking is
  # rejected rather than confirmed against unknown availability.
  def busy_intervals(raise_on_error: false)
    response = post_to_free_busy(free_busy_payload)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "Google free/busy returned #{response.code}" if raise_on_error

      return []
    end

    body = parse_body(response)
    Array(body.dig('calendars', 'primary', 'busy')).filter_map do |slot|
      start_time = parse_time(slot['start'])
      end_time = parse_time(slot['end'])
      next if start_time.blank? || end_time.blank?

      { start: start_time, end: end_time }
    end
  end

  private

  def free_busy_payload
    {
      timeMin: time_min.iso8601,
      timeMax: time_max.iso8601,
      items: [{ id: 'primary' }]
    }
  end

  def post_to_free_busy(payload)
    uri = URI("#{CALENDAR_API_BASE}/freeBusy")
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

  def parse_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_body(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    {}
  end
end
