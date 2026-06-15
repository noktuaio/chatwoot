# Orchestrates a billing currency switch: lock -> eligibility -> resolve price -> Stripe swap -> persist.
class Enterprise::Billing::SwitchCurrencyService
  include BillingHelper

  class Error < StandardError; end

  # Tags a cancelled sub so the deleted-webhook skips re-subscribing the default plan.
  SWITCH_METADATA_KEY = 'chatwoot_currency_switch'.freeze

  # Marks an in-flight switch to reject concurrent requests; cleared on completion or by the webhook.
  PENDING_CURRENCY_KEY = 'billing_currency_switch_pending'.freeze

  # A pending marker older than this is treated as abandoned so a crashed switch can't block forever.
  STALE_SWITCH_SECONDS = 10.minutes.to_i

  pattr_initialize [:account!, :currency!]

  def perform
    acquire_switch_lock!

    begin
      subscription = eligibility.subscription!
      resolver = Enterprise::Billing::PlanPriceResolver.new(subscription: subscription, target_currency: target_currency)
      plan = resolver.plan
      change = change_for(subscription, resolver.target_price_id, default_plan: Enterprise::Billing::PlanConfiguration.default_plan?(plan))

      new_subscription = executor.execute(subscription: subscription, change: change)

      persist_currency(build_custom_attributes(new_subscription, plan))
      Enterprise::Billing::ReconcilePlanFeaturesService.new(account: account).perform
    rescue Enterprise::Billing::CurrencySwitchEligibility::Error,
           Enterprise::Billing::PlanPriceResolver::Error,
           Enterprise::Billing::StripeCurrencySwitchExecutor::Error => e
      # Swap self-reverted; drop the marker and surface a single error type.
      clear_pending
      raise Error, e.message
    rescue Stripe::StripeError
      # Preflight Stripe failure (before any subscription change); clear the marker so a blip can't lock switching.
      clear_pending
      raise
    end
  end

  private

  # Check-and-set the marker under a row lock so concurrent switches can't both create a subscription.
  def acquire_switch_lock!
    account.with_lock do
      raise Error, I18n.t('errors.billing.switch_in_progress') if switch_in_progress?

      account.update!(custom_attributes: account.custom_attributes.merge(
        PENDING_CURRENCY_KEY => { 'currency' => target_currency, 'started_at' => Time.current.to_i }
      ))
    end
  end

  def switch_in_progress?
    marker = account.custom_attributes[PENDING_CURRENCY_KEY]
    return false if marker.blank?

    started_at = marker.is_a?(Hash) ? marker['started_at'].to_i : 0
    Time.current.to_i - started_at < STALE_SWITCH_SECONDS
  end

  def eligibility
    @eligibility ||= Enterprise::Billing::CurrencySwitchEligibility.new(account: account, currency: currency)
  end

  def executor
    @executor ||= Enterprise::Billing::StripeCurrencySwitchExecutor.new(account: account, target_currency: target_currency)
  end

  def target_currency
    @target_currency ||= Enterprise::Billing::Currencies.normalize(currency)
  end

  def change_for(subscription, new_price_id, default_plan:)
    {
      new_price_id: new_price_id,
      # Needed to re-create the subscription if the new-currency create fails.
      original_price_id: subscription['plan']['id'],
      quantity: subscription['quantity'],
      # Paid plans trial until paid-through; the free default plan switches immediately.
      paid_through: default_plan ? nil : subscription_period_end(subscription),
      default_plan: default_plan
    }
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

  def clear_pending
    account.update!(custom_attributes: account.custom_attributes.except(PENDING_CURRENCY_KEY))
  end

  def persist_currency(custom_attributes)
    account.update!(custom_attributes: custom_attributes.except(PENDING_CURRENCY_KEY))
  end
end
