# Supported billing currencies and their Stripe/locale mappings.
module Enterprise::Billing::Currencies
  DEFAULT = 'usd'.freeze

  SUPPORTED = %w[usd brl].freeze

  # Account locale label (e.g. 'pt_BR') => default currency; unlisted falls back to DEFAULT.
  LOCALE_DEFAULTS = {
    'pt_BR' => 'brl'
  }.freeze

  # Billing country override per currency; absent currencies (e.g. usd) keep Stripe's default.
  COUNTRY_BY_CURRENCY = {
    'brl' => 'BR'
  }.freeze

  # Preferred Stripe/checkout locale per currency; absent currencies keep Stripe's default.
  PREFERRED_LOCALE_BY_CURRENCY = {
    'brl' => 'pt-BR'
  }.freeze

  # Payment method types locked to one currency; types not listed (e.g. card) bill in any currency.
  CURRENCY_LOCKED_PAYMENT_METHOD_TYPES = {
    'pix' => 'brl',
    'boleto' => 'brl'
  }.freeze

  module_function

  def normalize(code)
    code.to_s.strip.downcase.presence
  end

  def supported?(code)
    SUPPORTED.include?(normalize(code))
  end

  # Map arbitrary input to a supported code, else DEFAULT.
  def to_supported(code)
    supported?(code) ? normalize(code) : DEFAULT
  end

  def for_locale(locale)
    LOCALE_DEFAULTS.fetch(locale.to_s, DEFAULT)
  end

  # Master switch for multi-currency billing; read raw so a super-admin toggle isn't cache-stale.
  def multi_currency_supported?
    ActiveModel::Type::Boolean.new.cast(InstallationConfig.find_by(name: 'MULTIPLE_CURRENCY_SUPPORTED')&.value)
  end

  def country_for(code)
    COUNTRY_BY_CURRENCY[to_supported(code)]
  end

  def preferred_locale_for(code)
    PREFERRED_LOCALE_BY_CURRENCY[to_supported(code)]
  end

  # Can a payment method of this Stripe type bill the given currency?
  def payment_method_supports?(payment_method_type, code)
    locked_currency = CURRENCY_LOCKED_PAYMENT_METHOD_TYPES[payment_method_type.to_s]
    locked_currency.nil? || locked_currency == to_supported(code)
  end
end
