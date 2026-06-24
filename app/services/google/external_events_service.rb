require 'net/http'

# Read-only listing of the mailbox owner's OWN Google Calendar events for a time
# window (P2 slice S4). Used to render the agent's real availability on the CRM
# calendar as muted/read-only context. Never raises — returns [] on any failure.
class Google::ExternalEventsService
  pattr_initialize [:channel!, :time_min!, :time_max!]

  CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'.freeze
  MAX_RESULTS = 100

  # Returns the events array on success ([] when the calendar is genuinely empty),
  # or nil on ANY failure so the caller can skip caching the failure.
  def events
    response = list_from_calendar
    return unless response.is_a?(Net::HTTPSuccess)

    body = parse_body(response)
    Array(body['items']).filter_map do |item|
      next if item['status'] == 'cancelled'

      {
        external_id: item['id'],
        title: item['summary'],
        starts_at: item.dig('start', 'dateTime') || item.dig('start', 'date'),
        ends_at: item.dig('end', 'dateTime') || item.dig('end', 'date'),
        all_day: item['start'].is_a?(Hash) && item['start'].key?('date') && !item['start'].key?('dateTime')
      }
    end
  rescue StandardError => e
    Rails.logger.error("Google::ExternalEventsService failed: #{e.message}")
    nil
  end

  private

  def list_from_calendar
    query = {
      timeMin: time_min.iso8601,
      timeMax: time_max.iso8601,
      singleEvents: 'true',
      orderBy: 'startTime',
      maxResults: MAX_RESULTS
    }
    uri = URI("#{CALENDAR_API_BASE}/calendars/primary/events")
    uri.query = URI.encode_www_form(query)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{access_token}"

    http.request(request)
  end

  def access_token
    Google::CalendarAccessTokenService.new(channel: channel).access_token
  end

  def parse_body(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    {}
  end
end
