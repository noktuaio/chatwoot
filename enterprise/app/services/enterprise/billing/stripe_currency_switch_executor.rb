# Stripe-side currency switch. Stripe forbids two currencies on one customer, so the old subscription
# is cancelled before the new one is created; on a create failure the original is re-created.
class Enterprise::Billing::StripeCurrencySwitchExecutor
  class Error < StandardError; end

  pattr_initialize [:account!, :target_currency!]

  # Returns the newly-created Stripe subscription.
  def execute(subscription:, change:)
    reconcile_default_payment_method unless change[:default_plan]

    previous_currency = account.billing_currency
    sync_customer_location(target_currency)

    begin
      replace_subscription(subscription, change)
    rescue StandardError
      # Swap reverted to the old currency — undo the location change too.
      sync_customer_location(previous_currency)
      raise
    end
  end

  private

  def replace_subscription(subscription, change)
    cancel_subscription(subscription)
    create_or_revert(change)
  rescue Stripe::StripeError => e
    raise Error, e.message
  end

  def create_or_revert(change)
    create_currency_subscription(change[:new_price_id], change, idempotency_key)
  rescue Stripe::StripeError
    # Old sub already cancelled; re-create the original to keep the customer subscribed, then re-raise.
    create_currency_subscription(change[:original_price_id], change, revert_idempotency_key)
    raise
  end

  def cancel_subscription(subscription)
    Stripe::Subscription.update(subscription.id, metadata: { Enterprise::Billing::SwitchCurrencyService::SWITCH_METADATA_KEY => 'true' })
    Stripe::Subscription.cancel(subscription.id, { prorate: false })
  rescue Stripe::StripeError
    # Clear the flag so a still-live sub isn't permanently skipped by the webhook guard.
    Stripe::Subscription.update(subscription.id, metadata: { Enterprise::Billing::SwitchCurrencyService::SWITCH_METADATA_KEY => '' })
    raise
  end

  def create_currency_subscription(price_id, change, idempotency_key)
    params = { customer: stripe_customer_id, items: [{ price: price_id, quantity: change[:quantity] }] }
    # trial_end preserves already-paid time so switching mid-cycle doesn't double-charge.
    params[:trial_end] = change[:paid_through] if change[:paid_through].present? && change[:paid_through] > Time.current.to_i
    Stripe::Subscription.create(params, { idempotency_key: idempotency_key })
  end

  # Fresh per attempt so a retry never replays a cancelled sub, and revert never collides with the create.
  def attempt_token
    @attempt_token ||= SecureRandom.uuid
  end

  def idempotency_key
    "switch-#{account.id}-#{attempt_token}"
  end

  def revert_idempotency_key
    "switch-revert-#{account.id}-#{attempt_token}"
  end

  def reconcile_default_payment_method
    Enterprise::Billing::DefaultPaymentMethodReconciler.new(account: account, currency: target_currency).reconcile
  end

  # Push the country override for currencies that need one (BRL/PIX); clear it otherwise so switching
  # to usd doesn't leave a stale BR address.
  def sync_customer_location(currency_code)
    country = Enterprise::Billing::Currencies.country_for(currency_code)
    locale = Enterprise::Billing::Currencies.preferred_locale_for(currency_code)

    Stripe::Customer.update(
      stripe_customer_id,
      address: { country: country.presence || '' },
      preferred_locales: locale.present? ? [locale] : []
    )
  end

  def stripe_customer_id
    account.custom_attributes['stripe_customer_id']
  end
end
