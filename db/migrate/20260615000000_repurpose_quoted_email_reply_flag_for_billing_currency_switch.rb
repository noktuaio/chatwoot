class RepurposeQuotedEmailReplyFlagForBillingCurrencySwitch < ActiveRecord::Migration[7.1]
  def up
    # The quoted_email_reply flag (deprecated) has been renamed to billing_currency_switch.
    # They share a bit position, so disable it on any accounts that had quoted_email_reply
    # enabled — otherwise they would silently start with billing_currency_switch on.
    Account.feature_billing_currency_switch.find_each(batch_size: 100) do |account|
      account.disable_features(:billing_currency_switch)
      account.save!(validate: false)
    end

    # Remove the stale quoted_email_reply entry from ACCOUNT_LEVEL_FEATURE_DEFAULTS.
    # ConfigLoader only adds new flags; it never removes renamed ones.
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.value = config.value.reject { |feature| feature['name'] == 'quoted_email_reply' }
    config.save!
    GlobalConfig.clear_cache
  end
end
