# Single source of truth for the billing currencies Chatwoot Cloud supports.
# Adding a new currency (e.g. EUR) is a one-line edit here plus the matching
# price_ids in CHATWOOT_CLOUD_PLANS and rates in CHATWOOT_CLOUD_TOPUP_OPTIONS.
module Enterprise::Billing::Currencies
  DEFAULT = 'usd'.freeze

  SUPPORTED = %w[usd brl].freeze

  # Account locale label (the enum label, e.g. 'pt_BR') => default currency.
  # Anything not listed falls back to DEFAULT.
  LOCALE_DEFAULTS = {
    'pt_BR' => 'brl'
  }.freeze

  # Used to keep the Stripe customer's location/currency in sync with the
  # account's billing currency.
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

  def country_for(code)
    COUNTRY_BY_CURRENCY[coerce(code)]
  end

  def preferred_locale_for(code)
    PREFERRED_LOCALE_BY_CURRENCY[coerce(code)]
  end
end
