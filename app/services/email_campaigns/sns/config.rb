module EmailCampaigns
  module Sns
    module Config
      module_function

      def topic_name
        ENV.fetch('EMAIL_CAMPAIGN_SNS_TOPIC', 'autonomia-email-campaign-events')
      end

      # Public SNS webhook endpoint AWS posts to. ENV override else FRONTEND_URL + path.
      def webhook_url
        ENV.fetch('EMAIL_CAMPAIGN_SNS_WEBHOOK_URL', nil).presence ||
          "#{ENV.fetch('FRONTEND_URL', 'https://app.chatwoot.com')}/email_campaigns/sns"
      end
    end
  end
end
