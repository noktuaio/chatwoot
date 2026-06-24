module EmailCampaigns
  module Ses
    # Ensures the SES configuration set publishes DELIVERY/BOUNCE/COMPLAINT to an SNS topic that
    # our public webhook is subscribed to. SNS side uses aws-sdk-sns; SES side stays gem-free.
    # Invoked OPERATIONALLY (rake/console at enable time), not per request.
    class EventDestinationEnsurer
      DESTINATION_NAME = 'autonomia-sns-events'.freeze
      EVENT_TYPES = %w[DELIVERY BOUNCE COMPLAINT].freeze

      def perform
        EmailCampaigns::Ses::ConfigurationSetEnsurer.new.perform
        topic_arn = ensure_topic
        subscribe_webhook(topic_arn)
        put_event_destination(topic_arn)
        topic_arn
      end

      private

      def sns
        @sns ||= Aws::SNS::Client.new(
          region: EmailCampaigns::Config.region,
          access_key_id: EmailCampaigns::Config.access_key_id,
          secret_access_key: EmailCampaigns::Config.secret_access_key
        )
      end

      def ensure_topic
        sns.create_topic(name: EmailCampaigns::Sns::Config.topic_name).topic_arn
      end

      def subscribe_webhook(topic_arn)
        sns.subscribe(topic_arn: topic_arn, protocol: webhook_protocol,
                      endpoint: EmailCampaigns::Sns::Config.webhook_url, return_subscription_arn: true)
      end

      def webhook_protocol
        EmailCampaigns::Sns::Config.webhook_url.start_with?('https') ? 'https' : 'http'
      end

      # gem-free SES: PUT a configuration-set event destination pointing DELIVERY/BOUNCE/
      # COMPLAINT to the SNS topic.
      def put_event_destination(topic_arn)
        EmailCampaigns::Ses::Client.new.put_configuration_set_event_destination(
          configuration_set: EmailCampaigns::Config.configuration_set_name,
          destination_name: DESTINATION_NAME,
          sns_topic_arn: topic_arn,
          event_types: EVENT_TYPES
        )
      end
    end
  end
end
