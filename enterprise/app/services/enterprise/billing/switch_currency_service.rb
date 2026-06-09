class Enterprise::Billing::SwitchCurrencyService
  include BillingHelper

  class Error < StandardError; end

  # Tags a cancelled sub so the deleted-webhook skips re-subscribing the default plan.
  SWITCH_METADATA_KEY = 'chatwoot_currency_switch'.freeze

  # Paid statuses that block a switch: delinquent (past_due, unpaid) or awaiting initial payment (incomplete, can still activate).
  BLOCKED_PAID_STATUSES = %w[past_due unpaid incomplete].freeze

  pattr_initialize [:account!, :currency!]

  # Ordered most-reversible first so any failure aborts cleanly: validate -> customer sync (idempotent,
  # before any cancellation) -> subscription replacement (self-reverting) -> local DB persist (last, alone).
  def perform
    validate!
    reject_unsettled_paid_subscription!

    subscriptions = live_subscriptions
    paid_subscription = subscriptions.find { |subscription| !default_price?(subscription) }
    validate_payment_method! if paid_subscription

    # Sync the customer before touching subscriptions: a failure here leaves nothing cancelled and the DB
    # untouched, so the controller's error matches state and a retry re-runs the whole switch.
    sync_stripe_customer_location

    attributes = paid_subscription ? switch_paid_plan(subscriptions, paid_subscription) : switch_free_plan(subscriptions)

    # Persist last: the local DB write is the only step after Stripe succeeds, and it gates retries via same_currency.
    persist_currency(attributes)
    Enterprise::Billing::ReconcilePlanFeaturesService.new(account: account).perform if paid_subscription
  end

  private

  def target_currency
    @target_currency ||= Enterprise::Billing::Currencies.normalize(currency)
  end

  def validate!
    raise Error, I18n.t('errors.billing.currency_switch_unavailable') unless Enterprise::Billing::Currencies.rollout_enabled?(account.locale)
    raise Error, I18n.t('errors.billing.unsupported_currency') unless Enterprise::Billing::Currencies.supported?(currency)
    raise Error, I18n.t('errors.billing.same_currency') if target_currency == account.billing_currency
    raise Error, I18n.t('errors.billing.stripe_customer_not_configured') if stripe_customer_id.blank?
  end

  # Free plan: recreate the default sub in the new currency so a later upgrade starts there. Returns the attributes to persist.
  def switch_free_plan(subscriptions)
    default_subscription = subscriptions.find { |subscription| default_price?(subscription) }
    return account.custom_attributes.merge('billing_currency' => target_currency) unless default_subscription

    recreated_default_attributes(subscriptions, default_subscription)
  end

  def recreated_default_attributes(subscriptions, default_subscription)
    plan = Enterprise::Billing::PlanConfiguration.default_plan
    change = {
      new_price_id: resolve_new_price_id(plan),
      original_price_id: default_subscription['plan']['id'],
      quantity: default_subscription['quantity'],
      key: default_subscription.id
    }

    build_custom_attributes(replace_subscriptions(subscriptions, change), plan)
  end

  # Replace all live subs with one paid sub in the target currency, preserving seats and paid-through. Returns the attributes to persist.
  def switch_paid_plan(subscriptions, paid_subscription)
    plan = current_plan(paid_subscription)
    raise Error, I18n.t('errors.billing.unknown_plan') if plan.blank?

    change = {
      new_price_id: resolve_new_price_id(plan),
      original_price_id: paid_subscription['plan']['id'],
      quantity: paid_subscription['quantity'],
      paid_through: subscriptions.filter_map { |subscription| subscription_period_end(subscription) }.max,
      key: paid_subscription.id
    }

    build_custom_attributes(replace_subscriptions(subscriptions, change), plan)
  end

  def resolve_new_price_id(plan)
    target_prices = Enterprise::Billing::PlanConfiguration.price_ids_by_currency(plan)[target_currency]
    raise Error, I18n.t('errors.billing.currency_not_available_for_plan') if target_prices.blank?

    target_prices.first
  end

  def current_plan(subscription)
    plan, = Enterprise::Billing::PlanConfiguration.find_plan_by_price_id(subscription['plan']['id'])
    plan || Enterprise::Billing::PlanConfiguration.find_plan_by_product_id(subscription['plan']['product'])
  end

  # Cancel old subs, create the new-currency sub; revert to the original plan on failure.
  # prorate:false (Stripe can't mix currencies); trial_end keeps the already-paid time.
  def replace_subscriptions(subscriptions, change)
    cancel_subscriptions(subscriptions)

    begin
      create_currency_subscription(change[:new_price_id], change, 'switch')
    rescue Stripe::StripeError => e
      create_currency_subscription(change[:original_price_id], change, 'switch-revert')
      raise Error, e.message
    end
  end

  def cancel_subscriptions(subscriptions)
    subscriptions.each do |subscription|
      Stripe::Subscription.update(subscription.id, metadata: { SWITCH_METADATA_KEY => 'true' })
      begin
        Stripe::Subscription.cancel(subscription.id, { prorate: false })
      rescue Stripe::StripeError
        # Clear the flag so a still-live sub isn't permanently skipped by the webhook guard.
        Stripe::Subscription.update(subscription.id, metadata: { SWITCH_METADATA_KEY => '' })
        raise
      end
    end
  end

  def create_currency_subscription(price_id, change, key_prefix)
    params = { customer: stripe_customer_id, items: [{ price: price_id, quantity: change[:quantity] }] }
    params[:trial_end] = change[:paid_through] if change[:paid_through].present? && change[:paid_through] > Time.current.to_i
    Stripe::Subscription.create(params, { idempotency_key: "#{key_prefix}-#{account.id}-#{change[:key]}" })
  end

  def build_custom_attributes(subscription, plan)
    account.custom_attributes.merge(
      'billing_currency' => target_currency,
      'stripe_price_id' => subscription['plan']['id'],
      'stripe_product_id' => subscription['plan']['product'],
      'plan_name' => plan['name'],
      'subscribed_quantity' => subscription['quantity'],
      'subscription_status' => subscription['status'],
      'subscription_ends_on' => subscription_ends_on(subscription)
    )
  end

  def default_price?(subscription)
    Enterprise::Billing::PlanConfiguration.plan_contains_price_id?(
      Enterprise::Billing::PlanConfiguration.default_plan, subscription['plan']['id']
    )
  end

  def persist_currency(custom_attributes)
    account.update!(custom_attributes: custom_attributes)
  end

  def sync_stripe_customer_location
    Stripe::Customer.update(
      stripe_customer_id,
      address: { country: Enterprise::Billing::Currencies.country_for(target_currency) },
      preferred_locales: [Enterprise::Billing::Currencies.preferred_locale_for(target_currency)]
    )
  end

  # Block the switch while a paid sub is unsettled, else the account currency/location changes but that sub stays/activates in the old currency.
  def reject_unsettled_paid_subscription!
    blocked = all_subscriptions.any? do |subscription|
      BLOCKED_PAID_STATUSES.include?(subscription.status) && !default_price?(subscription)
    end
    raise Error, I18n.t('errors.billing.past_due_subscription') if blocked
  end

  def all_subscriptions
    @all_subscriptions ||= Stripe::Subscription.list(customer: stripe_customer_id, status: 'all', limit: 100).data
  end

  # Includes trialing (a prior switch leaves the new sub trialing); unsettled paid subs are caught by reject_unsettled_paid_subscription!.
  def live_subscriptions
    all_subscriptions.select { |subscription| %w[active trialing].include?(subscription.status) }
  end

  def validate_payment_method!
    customer = Stripe::Customer.retrieve(stripe_customer_id)
    return if customer.invoice_settings.default_payment_method.present? || customer.default_source.present?

    payment_methods = Stripe::PaymentMethod.list(customer: stripe_customer_id, limit: 1)
    raise Error, I18n.t('errors.billing.no_payment_method') if payment_methods.data.empty?

    Stripe::Customer.update(stripe_customer_id, invoice_settings: { default_payment_method: payment_methods.data.first.id })
  end

  def stripe_customer_id
    account.custom_attributes['stripe_customer_id']
  end
end
