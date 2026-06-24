require 'net/http'

module Microsoft
  CalendarError = Class.new(StandardError)
  CalendarNoTeamsLicenseError = Class.new(CalendarError)
end

class Microsoft::CalendarEventService
  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze
  MAX_ATTEMPTS = 2
  DEFAULT_RETRY_AFTER = 2
  DEFAULT_REMINDER_MINUTES = 15

  def initialize(meeting:)
    @meeting = meeting
  end

  def perform
    create
  end

  def create
    return simulated_result if Crm::Config.calendar_ms_simulate?

    response = make_graph_request(event_payload)
    body = parse_response(response)

    {
      external_event_id: body['id'],
      join_url: body.dig('onlineMeeting', 'joinUrl') || body['onlineMeetingUrl']
    }
  end

  # Reads the event back from Microsoft Graph (mirrors Google::CalendarEventService#fetch_event)
  # so the RSVP sync can map each attendee's status.response. Returns the parsed body or nil;
  # never raises (best-effort, the caller swallows failures).
  def fetch_event(external_event_id)
    return if external_event_id.blank?

    response = get_event(external_event_id)
    return unless response.code.to_i == 200

    parse_response(response)
  rescue Microsoft::CalendarError, StandardError
    nil
  end

  # Reconciliation read (S7 2-way sync) — mirrors Google::CalendarEventService#event_state.
  # Distinguishes a real deletion/cancellation from a transient failure so the caller
  # never cancels a CRM meeting on a network blip. One of:
  #   { status: :deleted } | { status: :cancelled, body: } | { status: :active, body: } | { status: :unknown }
  def event_state(external_event_id)
    return { status: :unknown } if external_event_id.blank?

    response = get_event(external_event_id)
    code = response.code.to_i
    return { status: :deleted } if [404, 410].include?(code)
    return { status: :unknown } unless code == 200

    body = parse_response(response)
    return { status: :cancelled, body: body } if body['isCancelled'] == true

    { status: :active, body: body }
  rescue StandardError
    { status: :unknown }
  end

  # PATCHes an existing event (reschedule) with the new start/end. attributes
  # carries :starts_at, :ends_at, :timezone. Returns the parsed body on success,
  # raises Microsoft::CalendarError otherwise.
  def update_event(external_event_id, attributes)
    return simulated_update_result(external_event_id) if Crm::Config.calendar_ms_simulate?

    response = make_graph_update_request(external_event_id, update_payload(attributes))
    parse_response(response)
  end

  # DELETEs an event (cancel). 200/204/404/410 are all treated as success
  # (already gone). Raises Microsoft::CalendarError on any other non-2xx response.
  def delete_event(external_event_id)
    return true if Crm::Config.calendar_ms_simulate?
    return true if external_event_id.blank?

    response = send_delete_request(external_event_id)
    code = response.code.to_i
    return true if [200, 204, 404, 410].include?(code)

    raise Microsoft::CalendarError, "Microsoft Graph calendar event delete failed (#{response.code}): #{provider_error_message(response)}"
  end

  private

  def update_payload(attributes)
    attrs = attributes.with_indifferent_access
    {
      start: { dateTime: attrs[:starts_at].iso8601, timeZone: attrs[:timezone] },
      end: { dateTime: attrs[:ends_at].iso8601, timeZone: attrs[:timezone] }
    }
  end

  def make_graph_update_request(external_event_id, payload, attempt: 1)
    response = send_update_request(external_event_id, access_token, payload)

    case response.code.to_i
    when 200
      response
    when 401
      raise Microsoft::CalendarError, 'Microsoft Graph calendar event update failed: unauthorized after token refresh' if attempt >= MAX_ATTEMPTS

      @graph_token_service = nil
      make_graph_update_request(external_event_id, payload, attempt: attempt + 1)
    else
      raise Microsoft::CalendarError, "Microsoft Graph calendar event update failed (#{response.code}): #{provider_error_message(response)}"
    end
  end

  def send_update_request(external_event_id, token, payload)
    uri = URI("#{GRAPH_API_BASE}/me/events/#{CGI.escape(external_event_id)}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Patch.new(uri)
    request['Authorization'] = "Bearer #{token}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    http.request(request)
  end

  def send_delete_request(external_event_id)
    uri = URI("#{GRAPH_API_BASE}/me/events/#{CGI.escape(external_event_id)}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Delete.new(uri)
    request['Authorization'] = "Bearer #{access_token}"

    http.request(request)
  end

  def simulated_update_result(external_event_id)
    { 'id' => external_event_id, 'status' => 'confirmed' }
  end

  def get_event(external_event_id)
    uri = URI("#{GRAPH_API_BASE}/me/events/#{CGI.escape(external_event_id)}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    # Force start/end dateTime back in UTC so the reader never has to resolve a
    # Windows timezone id (e.g. "E. South America Standard Time"), which Rails/TZInfo
    # cannot parse — that would otherwise yield the wrong instant on 2-way sync.
    request['Prefer'] = 'outlook.timezone="UTC"'

    http.request(request)
  end

  attr_reader :meeting

  def make_graph_request(payload, attempt: 1)
    response = send_request(access_token, payload)

    case response.code.to_i
    when 201
      response
    when 401
      handle_unauthorized(payload, attempt)
    when 403
      handle_forbidden(response)
    when 429
      handle_rate_limit(response, payload, attempt)
    when 400..499
      raise Microsoft::CalendarError, "Microsoft Graph calendar event failed (#{response.code}): #{provider_error_message(response)}"
    else
      raise Microsoft::CalendarError, "Microsoft Graph calendar event failed (#{response.code}): #{provider_error_message(response)}"
    end
  end

  def send_request(token, payload)
    uri = URI("#{GRAPH_API_BASE}/me/events")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{token}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    http.request(request)
  end

  def handle_unauthorized(payload, attempt)
    raise Microsoft::CalendarError, 'Microsoft Graph calendar event failed: unauthorized after token refresh' if attempt >= MAX_ATTEMPTS

    @graph_token_service = nil
    make_graph_request(payload, attempt: attempt + 1)
  end

  def handle_forbidden(response)
    message = provider_error_message(response)
    raise Microsoft::CalendarNoTeamsLicenseError,
          "Microsoft Graph calendar event failed (403): #{message}. Check that the mailbox has a Teams license."
  end

  def handle_rate_limit(response, payload, attempt)
    raise Microsoft::CalendarError, 'Microsoft Graph calendar event failed: persistent rate limit (429)' if attempt >= MAX_ATTEMPTS

    sleep(retry_after_seconds(response))
    make_graph_request(payload, attempt: attempt + 1)
  end

  def access_token
    graph_token_service.access_token
  end

  def graph_token_service
    @graph_token_service ||= Microsoft::GraphTokenService.new(channel: channel)
  end

  def channel
    @channel ||= meeting.respond_to?(:email_channel) ? meeting.email_channel : meeting.inbox.channel
  end

  def event_payload
    {
      subject: meeting.title,
      body: { contentType: 'HTML', content: meeting.description.to_s },
      start: graph_datetime(meeting.starts_at),
      end: graph_datetime(meeting.ends_at),
      attendees: attendees_payload,
      isOnlineMeeting: true,
      onlineMeetingProvider: 'teamsForBusiness',
      isReminderOn: true,
      reminderMinutesBeforeStart: reminder_minutes_before_start
    }
  end

  def graph_datetime(value)
    {
      dateTime: value.iso8601,
      timeZone: meeting.timezone
    }
  end

  def attendees_payload
    meeting_participants.map do |participant|
      {
        emailAddress: {
          address: participant_email(participant),
          name: participant_name(participant)
        },
        type: 'required'
      }
    end
  end

  def meeting_participants
    return meeting.meeting_guests if meeting.respond_to?(:meeting_guests)

    meeting.participants
  end

  def participant_email(participant)
    participant.respond_to?(:email) ? participant.email : participant[:email]
  end

  def participant_name(participant)
    participant.respond_to?(:name) ? participant.name : participant[:name]
  end

  def reminder_minutes_before_start
    return meeting.reminder_minutes_before.to_i if meeting.respond_to?(:reminder_minutes_before)

    metadata = meeting.respond_to?(:metadata) ? (meeting.metadata || {}).to_h : {}
    value = metadata['reminder_minutes_before'].presence || metadata['reminder_minutes_before_start'].presence || DEFAULT_REMINDER_MINUTES
    value.to_i
  end

  def parse_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    raise Microsoft::CalendarError, 'Microsoft Graph calendar event failed: invalid JSON response'
  end

  def provider_error_message(response)
    parse_error_body(response.body).dig('error', 'message').presence || 'Unknown Microsoft Graph error'
  end

  def parse_error_body(body)
    JSON.parse(body)
  rescue JSON::ParserError, TypeError
    {}
  end

  def retry_after_seconds(response)
    response['Retry-After'].to_i.positive? ? response['Retry-After'].to_i : DEFAULT_RETRY_AFTER
  end

  def simulated_result
    {
      external_event_id: "sim-ms-#{meeting.id}",
      join_url: "https://teams.microsoft.com/l/meetup-join/sim/#{meeting.id}"
    }
  end
end
