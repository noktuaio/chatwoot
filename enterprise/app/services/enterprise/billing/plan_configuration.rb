# Reads CHATWOOT_CLOUD_PLANS and resolves Stripe price ids in a currency-aware,
# backward-compatible way. Owns all plan-shape parsing so the currency logic
# isn't scattered across the billing services.
#
# A plan's `price_ids` may be:
#   - a currency-keyed Hash: { 'usd' => ['price_x'], 'brl' => ['price_y'] }
#   - a flat Array (legacy):  ['price_x']           -> treated as usd
#   - a bare String (legacy): 'price_x'            -> treated as usd
module Enterprise::Billing::PlanConfiguration
  CLOUD_PLANS_CONFIG = 'CHATWOOT_CLOUD_PLANS'.freeze

  module_function

  def plans
    InstallationConfig.find_by(name: CLOUD_PLANS_CONFIG)&.value || []
  end

  def default_plan
    plans.first
  end

  def price_ids_by_currency(plan)
    raw = plan && plan['price_ids']
    case raw
    when Hash then raw.transform_keys { |key| Enterprise::Billing::Currencies.normalize(key) }
    when Array then { Enterprise::Billing::Currencies::DEFAULT => raw }
    when String then { Enterprise::Billing::Currencies::DEFAULT => [raw] }
    else {}
    end
  end

  # Price id to subscribe `plan` in `currency`. Falls back to usd, then to any
  # configured price, so a free plan with only a usd price still resolves.
  def price_id_for(plan, currency)
    by_currency = price_ids_by_currency(plan)
    code = Enterprise::Billing::Currencies.coerce(currency)

    (by_currency[code].presence ||
     by_currency[Enterprise::Billing::Currencies::DEFAULT].presence ||
     by_currency.values.flatten.compact).first
  end

  def plan_contains_price_id?(plan, price_id)
    price_ids_by_currency(plan).values.flatten.compact.include?(price_id)
  end

  # Webhook currency inference: [plan, currency] for a given price id, or [nil, nil].
  def find_plan_by_price_id(price_id)
    plans.each do |plan|
      price_ids_by_currency(plan).each do |currency, ids|
        return [plan, currency] if ids.include?(price_id)
      end
    end
    [nil, nil]
  end

  def find_plan_by_name(name)
    plans.find { |plan| plan['name'] == name }
  end

  def find_plan_by_product_id(product_id)
    plans.find { |plan| Array(plan['product_id']).include?(product_id) }
  end
end
