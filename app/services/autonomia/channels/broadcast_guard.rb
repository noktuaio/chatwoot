module Autonomia
  module Channels
    class BroadcastGuard
      BROADCAST_SUFFIX = '@broadcast'.freeze

      def self.blocked_conversation?(conversation)
        new(conversation: conversation).blocked?
      end

      def self.blocked_destination?(destination)
        normalized_destination(destination).end_with?(BROADCAST_SUFFIX)
      end

      def self.normalized_destination(destination)
        destination.to_s.strip.downcase
      end

      def initialize(conversation:)
        @conversation = conversation
      end

      def blocked?
        blocked_destination?(waha_chat_id) || blocked_destination?(contact_inbox_source_id)
      end

      private

      def blocked_destination?(destination)
        self.class.blocked_destination?(destination)
      end

      def waha_chat_id
        contact&.custom_attributes.to_h['waha_whatsapp_chat_id']
      end

      def contact_inbox_source_id
        contact_inbox&.source_id
      end

      def contact
        @conversation&.contact
      end

      def contact_inbox
        @conversation&.contact_inbox
      end
    end
  end
end
