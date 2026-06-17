# frozen_string_literal: true

class Account::MarketingAttributionService
  FIRST_TOUCH_COOKIE = 'cw_first_touch_attribution'
  LAST_TOUCH_COOKIE = 'cw_last_touch_attribution'

  UTM_FIELDS = %w[utm_source utm_medium utm_campaign utm_term utm_content utm_id].freeze
  CLICK_ID_FIELDS = %w[gclid gbraid wbraid dclid fbclid msclkid ttclid li_fat_id twclid rdt_cid].freeze
  CONTEXT_FIELDS = %w[referrer referrer_path landing_page source source_type captured_at].freeze
  ALLOWED_FIELDS = (UTM_FIELDS + CLICK_ID_FIELDS + CONTEXT_FIELDS).freeze
  SIGNAL_FIELDS = (UTM_FIELDS + CLICK_ID_FIELDS + %w[referrer source source_type]).freeze
  FIELD_MAX_LENGTH = 500
  SOURCE_TYPE_BY_MEDIUM = {
    'cpc' => 'paid_search',
    'ppc' => 'paid_search',
    'paid_search' => 'paid_search',
    'paidsearch' => 'paid_search',
    'sem' => 'paid_search',
    'paid_social' => 'paid_social',
    'paidsocial' => 'paid_social',
    'display' => 'paid_other',
    'cpm' => 'paid_other',
    'banner' => 'paid_other',
    'paid' => 'paid_other',
    'paid_other' => 'paid_other',
    'organic_search' => 'organic_search',
    'organicsearch' => 'organic_search',
    'organic_social' => 'organic_social',
    'organicsocial' => 'organic_social',
    'social' => 'organic_social',
    'email' => 'email',
    'partner' => 'partner',
    'affiliate' => 'partner',
    'referral' => 'referral'
  }.freeze

  CLICK_ID_ATTRIBUTION = {
    'gclid' => { 'source' => 'google', 'source_type' => 'paid_search' },
    'gbraid' => { 'source' => 'google', 'source_type' => 'paid_search' },
    'wbraid' => { 'source' => 'google', 'source_type' => 'paid_search' },
    'dclid' => { 'source' => 'google', 'source_type' => 'paid_other' },
    'fbclid' => { 'source' => 'meta', 'source_type' => 'paid_social' },
    'msclkid' => { 'source' => 'microsoft', 'source_type' => 'paid_search' },
    'ttclid' => { 'source' => 'tiktok', 'source_type' => 'paid_social' },
    'li_fat_id' => { 'source' => 'linkedin', 'source_type' => 'paid_social' },
    'twclid' => { 'source' => 'x', 'source_type' => 'paid_social' },
    'rdt_cid' => { 'source' => 'reddit', 'source_type' => 'paid_social' }
  }.freeze

  def initialize(account:, cookies:, request:)
    @account = account
    @cookies = cookies
    @request = request
  end

  def perform
    return unless ChatwootApp.chatwoot_cloud?
    return if account.blank?

    first_touch, last_touch, captured_from = attribution_payloads
    return if first_touch.blank? && last_touch.blank?

    store_attribution(first_touch, last_touch, captured_from)
  end

  private

  attr_reader :account, :cookies, :request

  def attribution_payloads
    first_touch = attribution_from_cookie(FIRST_TOUCH_COOKIE)
    last_touch = attribution_from_cookie(LAST_TOUCH_COOKIE)
    return [first_touch, last_touch, 'cookie'] if first_touch.present? || last_touch.present?

    referer_attribution = attribution_from_referer
    [referer_attribution, referer_attribution, referer_attribution.present? ? 'request_referer' : nil]
  end

  def store_attribution(first_touch, last_touch, captured_from)
    internal_attributes = account.internal_attributes || {}
    existing_attribution = internal_attributes['marketing_attribution'] || {}
    account.internal_attributes = internal_attributes.merge(
      'marketing_attribution' => {
        'first_touch' => existing_attribution['first_touch'].presence || first_touch || last_touch,
        'last_touch' => last_touch || first_touch,
        'captured_from' => captured_from,
        'stored_at' => Time.current.iso8601
      }
    )
    account.save!
  end

  def attribution_from_cookie(cookie_name)
    cookie_value = cookies[cookie_name]
    return if cookie_value.blank?

    payload = JSON.parse(CGI.unescape(cookie_value.to_s))
    sanitize_payload(payload)
  rescue JSON::ParserError, ArgumentError
    nil
  end

  def attribution_from_referer
    return if request.referer.blank?

    referer_url = URI.parse(request.referer)
    return unless referer_url.is_a?(URI::HTTP)

    query_params = Rack::Utils.parse_nested_query(referer_url.query)
    payload = {}

    (UTM_FIELDS + CLICK_ID_FIELDS).each do |field|
      payload[field] = query_params[field] if query_params[field].present?
    end

    return if payload.blank?

    payload['landing_page'] = sanitized_landing_page(referer_url, payload)
    payload.merge!(derived_attribution(payload))
    payload['captured_at'] = Time.current.iso8601
    sanitize_payload(payload)
  rescue URI::InvalidURIError, Rack::QueryParser::InvalidParameterError
    nil
  end

  def sanitize_payload(payload)
    return unless payload.is_a?(Hash)

    sanitized_payload = payload.slice(*ALLOWED_FIELDS).transform_values do |value|
      value.to_s.strip.first(FIELD_MAX_LENGTH)
    end.compact_blank

    sanitized_payload if sanitized_payload.slice(*SIGNAL_FIELDS).present?
  end

  def sanitized_landing_page(url, payload)
    landing_page_url = url.dup
    landing_page_url.query = nil
    landing_page_url.fragment = nil

    allowed_query = payload.slice(*(UTM_FIELDS + CLICK_ID_FIELDS)).to_query
    landing_page_url.query = allowed_query if allowed_query.present?
    landing_page_url.to_s
  end

  def derived_attribution(payload)
    utm_source = normalized_token(payload['utm_source'])
    source_type = source_type_from_medium(payload['utm_medium'])
    click_attribution = click_id_attribution(payload)

    {
      'source' => utm_source.presence || click_attribution&.dig('source'),
      'source_type' => source_type.presence ||
        (payload['utm_medium'].present? ? 'unknown' : nil) ||
        click_attribution&.dig('source_type')
    }.compact_blank
  end

  def click_id_attribution(payload)
    CLICK_ID_FIELDS.each do |field|
      return CLICK_ID_ATTRIBUTION[field] if payload[field].present?
    end

    nil
  end

  def source_type_from_medium(medium)
    SOURCE_TYPE_BY_MEDIUM[normalized_token(medium)]
  end

  def normalized_token(value)
    value.to_s.strip.downcase.gsub(/\s+/, '_')
  end
end
