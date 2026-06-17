require 'net/http'

module EmailCampaigns
  module Sns
    # Verifies the SNS signature, auto-confirms subscriptions, and dispatches SES event
    # notifications to the EventProcessor. Never raises on malformed payloads (returns nil);
    # only an invalid SNS signature raises InvalidSignature (controller -> 403).
    class MessageHandler
      class InvalidSignature < StandardError; end

      def initialize(raw_body)
        @raw = raw_body.to_s
        @msg = JSON.parse(@raw)
      rescue JSON::ParserError
        @msg = {}
      end

      def process
        raise InvalidSignature unless verified?

        case @msg['Type']
        when 'SubscriptionConfirmation' then confirm_subscription
        when 'Notification'             then handle_notification
        end
      end

      private

      def verified?
        return false if @msg.blank?

        Aws::SNS::MessageVerifier.new.authentic?(@raw)
      rescue StandardError
        false
      end

      # Auto-confirm: GET the SubscribeURL (AWS-hosted https, already part of a verified message).
      def confirm_subscription
        url = @msg['SubscribeURL']
        return if url.blank?

        Net::HTTP.get_response(URI.parse(url))
      end

      def handle_notification
        ses_event = JSON.parse(@msg['Message'].to_s)
        EmailCampaigns::Sns::EventProcessor.new(ses_event).process
      rescue JSON::ParserError
        nil
      end
    end
  end
end
