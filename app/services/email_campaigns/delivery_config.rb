module EmailCampaigns
  # Onda 2 delivery-specific config (additive; keeps EmailCampaigns::Config untouched).
  # SES send-rate throttle. List-Unsubscribe URLs come from EmailCampaigns::Unsubscribe::Token (Onda D).
  module DeliveryConfig
    module_function

    def max_send_rate
      ENV.fetch('EMAIL_CAMPAIGN_SES_MAX_SEND_RATE', 1).to_f
    end
  end
end
