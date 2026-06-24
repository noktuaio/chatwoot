module Crm
  module Webhooks
    # Bridges Crm::Activity lifecycle events onto the native Events dispatcher so
    # WebhookListener can fan them out to account webhooks.
    #
    # Called from an after_commit hook on Crm::Activity (NOT from ActivityLogger,
    # which runs inside the mover/closer/creator transaction — see plan B2). The
    # caller passes IDS ONLY; the downstream listener reloads records by id.
    #
    # EVENT_MAP keys are the REAL event_type strings written by the CRM services
    # (verified: creator.rb 'create', mover.rb 'move', closer.rb 'won'/'lost'/'reopen',
    # cards_controller.rb 'archive'). Values are the dotted dispatcher constants.
    # This is an explicit allowlist: any event_type not listed (ai_*, follow_up_*,
    # conversation_sync, conversation_dedup_reuse, ...) is silently ignored for the
    # MVP (plan D3).
    class Emitter
      EVENT_MAP = {
        'create' => Events::Types::CRM_CARD_CREATED,
        'move' => Events::Types::CRM_CARD_MOVED,
        'won' => Events::Types::CRM_CARD_WON,
        'lost' => Events::Types::CRM_CARD_LOST,
        'reopen' => Events::Types::CRM_CARD_REOPENED,
        'archive' => Events::Types::CRM_CARD_ARCHIVED
      }.freeze

      def initialize(account_id:, card_id:, activity_id:, event_type:, changed_attributes: nil)
        @account_id = account_id
        @card_id = card_id
        @activity_id = activity_id
        @event_type = event_type.to_s
        @changed_attributes = changed_attributes
      end

      def self.emit(...)
        new(...).perform
      end

      def perform
        event = EVENT_MAP[@event_type]
        return if event.blank?
        return unless any_account_webhook_subscribed?(event)

        Rails.configuration.dispatcher.dispatch(
          event,
          Time.zone.now,
          account_id: @account_id,
          card_id: @card_id,
          activity_id: @activity_id,
          event: event,
          changed_attributes: @changed_attributes
        )
      end

      private

      # Early-exit (plan R1): skip enqueuing EventDispatcherJob unless at least one
      # account webhook subscribes this event, to avoid flooding the queue on every
      # Crm::Activity write (AI auto-move / bulk move amplify this).
      def any_account_webhook_subscribed?(event)
        account = Account.find_by(id: @account_id)
        return false if account.blank?

        account.webhooks.account_type.any? { |webhook| webhook.subscriptions.to_a.include?(event) }
      end
    end
  end
end
