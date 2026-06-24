module Crm
  class WhatsappGroupDetector
    NON_DIRECT_JID_SUFFIXES = %w[@g.us @broadcast @newsletter].freeze
    WHATSAPP_CHANNEL_TYPES = %w[Channel::Whatsapp Channel::Api].freeze

    # Non-1:1 WhatsApp JIDs (WAHA/Evolution): groups end with @g.us, broadcasts
    # with @broadcast (incl. status@broadcast), channels with @newsletter.
    # Scoped to WhatsApp-capable channels so email/web source_ids never match.
    def self.group_conversation?(conversation)
      return false unless WHATSAPP_CHANNEL_TYPES.include?(conversation&.inbox&.channel_type)

      conversation.contact_inbox&.source_id.to_s.downcase.end_with?(*NON_DIRECT_JID_SUFFIXES)
    end
  end
end
