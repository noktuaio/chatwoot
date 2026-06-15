# Orchestrates a billing currency switch:
#   acquire per-account lock -> eligibility (no mutation) -> resolve target price -> Stripe swap
#   (self-reverting) -> persist local state (last). Each concern lives in its own collaborator so this
# stays a thin coordinator. The pending marker is set under a row lock first, so a second concurrent
# switch is rejected before it can create a duplicate Stripe subscription. Any failure aborts before
# persisting, so Chatwoot is never left ahead of Stripe; the rare window where Stripe succeeds but the
# local persist fails is reconciled by the subscription webhook, which also clears the pending marker.
class Enterprise::Billing::SwitchCurrencyService
  include BillingHelper

  class Error < StandardError; end

  # Tags a cancelled sub so the deleted-webhook skips re-subscribing the default plan.
  SWITCH_METADATA_KEY = 'chatwoot_currency_switch'.freeze

  # Records the in-flight switch so a second concurrent request is rejected and a crash mid-switch is
  # visible; cleared on success or by the subscription webhook once it reconciles the state from Stripe.
  PENDING_CURRENCY_KEY = 'billing_currency_switch_pending'.freeze

  # A pending marker older than this is treated as abandoned (e.g. a crashed prior attempt), so a stuck
  # marker can't block switches forever. Switches complete in seconds, so this is comfortably generous.
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
      # The Stripe swap self-reverted, so drop the pending marker and surface a single error type.
      clear_pending
      raise Error, e.message
    end
  end

  private

  # Reject a second switch for this account while one is in flight. The check-and-set runs under a row
  # lock so two concurrent requests can't both pass it and create duplicate Stripe subscriptions.
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
      # Original price is needed to re-create the subscription if the new-currency create fails.
      original_price_id: subscription['plan']['id'],
      quantity: subscription['quantity'],
      # Paid plans preserve paid-through (new sub trials until then); the free default plan switches
      # immediately to an active sub, so a default-plan account can switch again any time.
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
