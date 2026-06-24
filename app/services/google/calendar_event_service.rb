require 'net/http'
require 'ostruct'

module Google
  CalendarError = Class.new(StandardError)
end

class Google::CalendarEventService
  pattr_initialize [:channel!, :meeting_params!, :guests!]

  CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'.freeze
  DEFAULT_REMINDER_MINUTES = 15

  def create
    return simulated_result if Crm::Config.calendar_google_simulate?

    response = post_to_calendar(event_payload)
    body = parse_body(response)

    raise_calendar_error(response, body) unless response.is_a?(Net::HTTPSuccess)

    hangout_link = body['hangoutLink'].presence || video_entry_point_uri(body)
    OpenStruct.new(
      external_event_id: body['id'],
      hangoutLink: hangout_link,
      online_meeting_url: hangout_link,
      provider: :google
    )
  end

  # Read-only fetch of a single event (used by RSVP sync). Returns the parsed
  # body on success, nil otherwise. Reuses the same auth/HTTP helpers as create.
  def fetch_event(external_event_id)
    return if external_event_id.blank?

    response = get_from_calendar(external_event_id)
    return unless response.is_a?(Net::HTTPSuccess)

    parse_body(response)
  end

  # Reconciliation read (S7 2-way sync): returns the event's STATE so the caller can
  # tell a real deletion/cancellation apart from a transient failure (and never
  # cancels a CRM meeting on a network blip). One of:
  #   { status: :deleted }              — 404/410, the event is gone
  #   { status: :cancelled, body: ... } — 200 but status == 'cancelled'
  #   { status: :active,    body: ... } — 200, live event
  #   { status: :unknown }              — any other non-2xx (do NOT act)
  def event_state(external_event_id)
    return { status: :unknown } if external_event_id.blank?

    response = get_from_calendar(external_event_id)
    code = response.code.to_i
    return { status: :deleted } if [404, 410].include?(code)
    return { status: :unknown } unless response.is_a?(Net::HTTPSuccess)

    body = parse_body(response)
    return { status: :cancelled, body: body } if body['status'].to_s == 'cancelled'

    { status: :active, body: body }
  rescue StandardError
    { status: :unknown }
  end

  # PATCHes an existing event (reschedule). attributes carries :starts_at, :ends_at
  # and :timezone. Returns the parsed body on success, raises CalendarError otherwise.
  def update_event(external_event_id, attributes)
    return simulated_update_result(external_event_id) if Crm::Config.calendar_google_simulate?

    response = patch_to_calendar(external_event_id, update_payload(attributes))
    body = parse_body(response)

    raise_calendar_error(response, body) unless response.is_a?(Net::HTTPSuccess)

    body
  end

  # DELETEs an event (cancel). 200/204/404/410 are all treated as success
  # (already gone). Raises CalendarError on any other non-2xx response.
  def delete_event(external_event_id)
    return true if Crm::Config.calendar_google_simulate?
    return true if external_event_id.blank?

    response = delete_from_calendar(external_event_id)
    code = response.code.to_i
    return true if [200, 204, 404, 410].include?(code)

    raise_calendar_error(response, parse_body(response))
  end

  private

  def update_payload(attributes)
    attrs = attributes.with_indifferent_access
    {
      start: { dateTime: attrs[:starts_at].iso8601, timeZone: attrs[:timezone] },
      end: { dateTime: attrs[:ends_at].iso8601, timeZone: attrs[:timezone] }
    }
  end

  def patch_to_calendar(external_event_id, payload)
    uri = URI("#{CALENDAR_API_BASE}/calendars/primary/events/#{CGI.escape(external_event_id)}?sendUpdates=all&conferenceDataVersion=1")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Patch.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    http.request(request)
  end

  def delete_from_calendar(external_event_id)
    uri = URI("#{CALENDAR_API_BASE}/calendars/primary/events/#{CGI.escape(external_event_id)}?sendUpdates=all")
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

  def get_from_calendar(external_event_id)
    uri = URI("#{CALENDAR_API_BASE}/calendars/primary/events/#{CGI.escape(external_event_id)}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{access_token}"

    http.request(request)
  end

  def event_payload
    {
      summary: params[:title],
      description: params[:description].to_s,
      start: time_payload(params[:starts_at]),
      end: time_payload(params[:ends_at]),
      attendees: attendees_payload,
      conferenceData: conference_data_payload,
      reminders: reminders_payload
    }.tap do |payload|
      if params[:card_id].present?
        payload[:extendedProperties] = { shared: { crm_card_id: params[:card_id].to_s } }
      end
    end
  end

  def attendees_payload
    guests.map do |guest|
      guest_params = guest.with_indifferent_access

      {
        email: guest_params[:email],
        displayName: guest_params[:name],
        responseStatus: 'needsAction'
      }.compact
    end
  end

  def conference_data_payload
    {
      createRequest: {
        requestId: SecureRandom.uuid,
        conferenceSolutionKey: { type: 'hangoutsMeet' }
      }
    }
  end

  def reminders_payload
    {
      useDefault: false,
      overrides: [
        { method: 'popup', minutes: reminder_minutes },
        { method: 'email', minutes: reminder_minutes }
      ]
    }
  end

  def reminder_minutes
    (params[:reminder_minutes].presence || DEFAULT_REMINDER_MINUTES).to_i
  end

  def time_payload(value)
    { dateTime: value.iso8601, timeZone: params[:timezone] }
  end

  def post_to_calendar(payload)
    uri = URI("#{CALENDAR_API_BASE}/calendars/primary/events?sendUpdates=all&conferenceDataVersion=1")
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

  def parse_body(response)
    JSON.parse(response.body)
  rescue JSON::ParserError, TypeError
    {}
  end

  def video_entry_point_uri(body)
    Array(body.dig('conferenceData', 'entryPoints')).find { |entry_point| entry_point['entryPointType'] == 'video' }&.dig('uri')
  end

  def raise_calendar_error(response, body)
    Rails.logger.error("Google Calendar API error (#{response.code}): #{body.dig('error', 'message')}")
    raise Google::CalendarError, "google_calendar_event_create_failed (#{response.code})"
  end

  def params
    @params ||= meeting_params.with_indifferent_access
  end

  def simulated_result
    identifier = params[:meeting_id].presence || params[:uuid].presence || params[:id].presence || 'unknown'
    {
      external_event_id: "sim-google-#{identifier}",
      join_url: "https://meet.google.com/sim-#{identifier}"
    }
  end
end
