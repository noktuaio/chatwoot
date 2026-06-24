class Crm::Meetings::Sanitizer
  CONTROL_CHAR_REGEX = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/.freeze
  CRLF_REGEX = /[\r\n]+/.freeze
  MAX_TITLE_LENGTH = 255
  MAX_GUEST_NAME_LENGTH = 255
  MAX_DESCRIPTION_LENGTH = 5000

  def initialize(params)
    @params = params.deep_dup.with_indifferent_access
  end

  def sanitize!
    @params[:title] = sanitize_string(@params[:title], max: MAX_TITLE_LENGTH)
    @params[:description] = sanitize_html(@params[:description])
    @params[:extra_guests] = sanitize_guest_emails(@params[:extra_guests] || [])
    @params
  end

  def self.sanitize_guest_name(name)
    return '' if name.blank?

    name.to_s.gsub(CRLF_REGEX, ' ').gsub(CONTROL_CHAR_REGEX, '').strip.truncate(MAX_GUEST_NAME_LENGTH)
  end

  private

  def sanitize_string(value, max:)
    return '' if value.blank?

    value.to_s.gsub(CRLF_REGEX, ' ').gsub(CONTROL_CHAR_REGEX, '').strip.truncate(max)
  end

  def sanitize_html(value)
    return '' if value.blank?

    ActionView::Base.full_sanitizer.sanitize(value.to_s).strip.truncate(MAX_DESCRIPTION_LENGTH)
  end

  def sanitize_guest_emails(emails)
    Array(emails).filter_map do |email|
      normalized = email.to_s.strip
      next if normalized.blank?

      parsed = Mail::Address.new(normalized)
      address = parsed.address
      raise ArgumentError, 'invalid_guest_email' unless address.present? && address == normalized && address.include?('@')

      normalized
    end
  rescue Mail::Field::ParseError => e
    raise ArgumentError, "invalid_guest_email: #{e.message}"
  end
end
