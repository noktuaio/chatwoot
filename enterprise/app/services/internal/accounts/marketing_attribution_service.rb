# frozen_string_literal: true

class Internal::Accounts::MarketingAttributionService
  FIRST_TOUCH_COOKIE = 'cw_first_touch_attribution'
  LAST_TOUCH_COOKIE = 'cw_last_touch_attribution'

  ALLOWED_FIELDS = %w[
    utm_source utm_medium utm_campaign utm_term utm_content utm_id
    gclid gbraid wbraid dclid fbclid msclkid ttclid li_fat_id twclid rdt_cid
    referrer referrer_path landing_page source source_type captured_at
  ].freeze
  SIGNAL_FIELDS = %w[
    utm_source utm_medium utm_campaign utm_term utm_content utm_id
    gclid gbraid wbraid dclid fbclid msclkid ttclid li_fat_id twclid rdt_cid
    referrer source source_type
  ].freeze
  FIELD_MAX_LENGTH = 500

  pattr_initialize [:account!, :cookies!]

  def perform
    return unless ChatwootApp.chatwoot_cloud?

    first_touch, last_touch = attribution_payloads
    return if first_touch.blank? && last_touch.blank?

    store_attribution(first_touch, last_touch)
  end

  private

  def attribution_payloads
    [
      attribution_from_cookie(FIRST_TOUCH_COOKIE),
      attribution_from_cookie(LAST_TOUCH_COOKIE)
    ]
  end

  def store_attribution(first_touch, last_touch)
    internal_attributes = account.internal_attributes || {}
    existing_attribution = internal_attributes['marketing_attribution'] || {}

    account.update!(
      internal_attributes: internal_attributes.merge(
        'marketing_attribution' => {
          'first_touch' => existing_attribution['first_touch'].presence || first_touch || last_touch,
          'last_touch' => last_touch || first_touch,
          'captured_from' => 'cookie',
          'stored_at' => Time.current.iso8601
        }
      )
    )
  end

  def attribution_from_cookie(cookie_name)
    cookie_value = cookies[cookie_name]
    return if cookie_value.blank?

    sanitize_payload(JSON.parse(CGI.unescape(cookie_value.to_s)))
  rescue JSON::ParserError, ArgumentError
    nil
  end

  def sanitize_payload(payload)
    return unless payload.is_a?(Hash)

    sanitized_payload = payload.slice(*ALLOWED_FIELDS).transform_values do |value|
      value.to_s.strip.first(FIELD_MAX_LENGTH)
    end.compact_blank

    sanitized_payload if sanitized_payload.slice(*SIGNAL_FIELDS).present?
  end
end
