require 'net/http'

# Reads the connected Microsoft mailbox's busy intervals for a time window via the
# Graph /me/calendar/getSchedule endpoint. Channel-keyed (reuses
# Microsoft::GraphTokenService for auth, the same path CalendarEventService uses).
# Best-effort: returns [] on any non-2xx response so availability never breaks
# scheduling.
class Microsoft::FreeBusyService
  pattr_initialize [:channel!, :time_min!, :time_max!, :email!]

  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze
  BUSY_STATUSES = %w[busy oof tentative workingElsewhere].freeze

  # Raised only when raise_on_error:true so a caller that must fail CLOSED (the
  # public-booking slot re-check) can reject instead of treating a provider
  # outage as "no busy intervals".
  class Error < StandardError; end

  # Returns an array of { start: Time, end: Time } busy blocks.
  # raise_on_error:false (default) — best-effort: [] on any non-2xx (display path).
  # raise_on_error:true — fail-closed: a non-2xx response raises so booking is
  # rejected rather than confirmed against unknown availability.
  def busy_intervals(raise_on_error: false)
    response = post_to_get_schedule(get_schedule_payload)
    unless response.code.to_i == 200
      raise Error, "Microsoft getSchedule returned #{response.code}" if raise_on_error

      return []
    end

    body = parse_body(response)
    schedule = Array(body['value']).first
    Array(schedule&.dig('scheduleItems')).filter_map do |item|
      next unless BUSY_STATUSES.include?(item['status'].to_s)

      start_time = parse_time(item.dig('start', 'dateTime'), item.dig('start', 'timeZone'))
      end_time = parse_time(item.dig('end', 'dateTime'), item.dig('end', 'timeZone'))
      next if start_time.blank? || end_time.blank?

      { start: start_time, end: end_time }
    end
  end

  private

  def get_schedule_payload
    {
      schedules: [email],
      startTime: { dateTime: time_min.utc.iso8601, timeZone: 'UTC' },
      endTime: { dateTime: time_max.utc.iso8601, timeZone: 'UTC' },
      availabilityViewInterval: 30
    }
  end

  def post_to_get_schedule(payload)
    uri = URI("#{GRAPH_API_BASE}/me/calendar/getSchedule")
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
    Microsoft::GraphTokenService.new(channel: channel).access_token
  end

  # Graph returns naive datetimes paired with a timeZone field (UTC here, since we
  # request the window in UTC). Interpret in that zone, fall back to UTC.
  def parse_time(value, zone)
    return if value.blank?

    parsed = Time.find_zone(zone.presence || 'UTC')&.parse(value.to_s) || Time.zone.parse(value.to_s)
    parsed&.utc
  rescue ArgumentError, TypeError
    nil
  end

  def parse_body(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    {}
  end
end
