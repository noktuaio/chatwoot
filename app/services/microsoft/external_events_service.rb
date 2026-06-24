require 'net/http'

# Read-only listing of the mailbox owner's OWN Microsoft Graph calendar events
# for a time window (P2 slice S4) — the Microsoft parity of
# Google::ExternalEventsService. Never raises — returns [] on any failure.
class Microsoft::ExternalEventsService
  pattr_initialize [:channel!, :time_min!, :time_max!]

  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze
  MAX_RESULTS = 100

  # Returns the events array on success ([] when empty), or nil on ANY failure so
  # the caller can skip caching the failure.
  def events
    response = list_calendar_view
    return unless response.code.to_i == 200

    body = parse_body(response)
    Array(body['value']).filter_map do |item|
      next if item['isCancelled'] == true

      {
        external_id: item['id'],
        title: item['subject'],
        starts_at: item.dig('start', 'dateTime'),
        ends_at: item.dig('end', 'dateTime'),
        all_day: item['isAllDay'] == true
      }
    end
  rescue StandardError => e
    Rails.logger.error("Microsoft::ExternalEventsService failed: #{e.message}")
    nil
  end

  private

  def list_calendar_view
    query = {
      startDateTime: time_min.utc.iso8601,
      endDateTime: time_max.utc.iso8601,
      '$top' => MAX_RESULTS,
      '$orderby' => 'start/dateTime'
    }
    uri = URI("#{GRAPH_API_BASE}/me/calendarView")
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
    Microsoft::GraphTokenService.new(channel: channel).access_token
  end

  def parse_body(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    {}
  end
end
