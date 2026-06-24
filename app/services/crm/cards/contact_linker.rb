module Crm
  module Cards
    class ContactLinker
      def initialize(card:, contact:, actor:)
        @card = card
        @contact = contact
        @actor = actor
      end

      def link
        ActiveRecord::Base.transaction do
          @card.update!(contact: @contact, last_activity_at: Time.current)
          log_activity('contact_linked')
          @card
        end
      end

      def unlink
        ActiveRecord::Base.transaction do
          contact_id = @card.contact_id
          @card.update!(contact_id: nil, last_activity_at: Time.current)
          log_activity('contact_unlinked', contact_id: contact_id)
          @card
        end
      end

      private

      def log_activity(event_type, contact_id: @contact&.id)
        Crm::ActivityLogger.new(
          card: @card,
          actor: @actor,
          event_type: event_type,
          payload: { contact_id: contact_id }.compact
        ).perform
      end
    end
  end
end
