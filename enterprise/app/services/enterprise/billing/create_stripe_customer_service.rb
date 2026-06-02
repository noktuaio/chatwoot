class Enterprise::Billing::CreateStripeCustomerService
  include BillingHelper

  pattr_initialize [:account!]

  DEFAULT_QUANTITY = 2

  def perform
    active_sub = active_subscription
    return false if active_sub && !default_plan_subscription?(active_sub)

    customer_id = prepare_customer_id
    subscription = active_sub || Stripe::Subscription.create(customer: customer_id, items: [{ price: price_id, quantity: default_quantity }])
    custom_attributes = build_custom_attributes(customer_id, subscription)
    custom_attributes.except!('is_creating_customer')

    account.update!(custom_attributes: custom_attributes)
    Enterprise::Billing::ReconcilePlanFeaturesService.new(account: account).perform
    true
  end

  private

  def prepare_customer_id
    customer_id = account.custom_attributes['stripe_customer_id']
    if customer_id.blank?
      customer = Stripe::Customer.create(
        {
          name: account.name,
          email: billing_email,
          address: { country: Enterprise::Billing::Currencies.country_for(account.billing_currency) },
          preferred_locales: [Enterprise::Billing::Currencies.preferred_locale_for(account.billing_currency)]
        }
      )
      customer_id = customer.id
    end
    customer_id
  end

  def default_quantity
    default_plan['default_quantity'] || DEFAULT_QUANTITY
  end

  def billing_email
    account.administrators.first.email
  end

  def default_plan
    @default_plan ||= Enterprise::Billing::PlanConfiguration.default_plan
  end

  def price_id
    Enterprise::Billing::PlanConfiguration.price_id_for(default_plan, account.billing_currency)
  end

  def active_subscription
    stripe_customer_id = account.custom_attributes['stripe_customer_id']
    return nil if stripe_customer_id.blank?

    Stripe::Subscription.list(
      {
        customer: stripe_customer_id,
        status: 'active',
        limit: 1
      }
    ).data.first
  end

  def default_plan_subscription?(subscription)
    Enterprise::Billing::PlanConfiguration.plan_contains_price_id?(default_plan, subscription['plan']['id'])
  end

  def build_custom_attributes(customer_id, subscription)
    (account.custom_attributes || {}).merge(
      'stripe_customer_id' => customer_id,
      'stripe_price_id' => subscription['plan']['id'],
      'stripe_product_id' => subscription['plan']['product'],
      'plan_name' => default_plan['name'],
      'subscribed_quantity' => subscription['quantity'],
      'subscription_status' => subscription['status'],
      'subscription_ends_on' => subscription_ends_on(subscription),
      'billing_currency' => account.billing_currency
    )
  end
end
