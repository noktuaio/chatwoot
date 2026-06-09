# Supported billing currencies and their Stripe/locale mappings.
module Enterprise::Billing::Currencies
  DEFAULT = 'usd'.freeze

  SUPPORTED = %w[usd brl].freeze

  # Account locale label (e.g. 'pt_BR') => default currency; unlisted falls back to DEFAULT.
  LOCALE_DEFAULTS = {
    'pt_BR' => 'brl'
  }.freeze

  COUNTRY_BY_CURRENCY = {
    'usd' => 'US',
    'brl' => 'BR'
  }.freeze

  PREFERRED_LOCALE_BY_CURRENCY = {
    'usd' => 'en',
    'brl' => 'pt-BR'
  }.freeze

  module_function

  def normalize(code)
    code.to_s.strip.downcase.presence
  end

  def supported?(code)
    SUPPORTED.include?(normalize(code))
  end

  # Coerce arbitrary input to a usable supported code, else DEFAULT.
  def coerce(code)
    supported?(code) ? normalize(code) : DEFAULT
  end

  def for_locale(locale)
    LOCALE_DEFAULTS.fetch(locale.to_s, DEFAULT)
  end

  # Currency switching is rolled out only to locales with a non-default currency (e.g. pt_BR).
  def rollout_enabled?(locale)
    LOCALE_DEFAULTS.key?(locale.to_s)
  end

  def country_for(code)
    COUNTRY_BY_CURRENCY[coerce(code)]
  end

  def preferred_locale_for(code)
    PREFERRED_LOCALE_BY_CURRENCY[coerce(code)]
  end
end
