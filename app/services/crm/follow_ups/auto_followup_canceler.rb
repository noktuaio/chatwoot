module Crm
  module FollowUps
    # Primary auto-stop path for the AI follow-up cadence: when the contact
    # REPLIES (inbound message) — or opts out via STOP/SAIR — cancel every
    # pending ai_followup touch on the card immediately, instead of waiting for
    # the next due sweep. Invoked from Crm::Conversations::CardSyncer on every
    # synced message.
    #
    # Strictly guarded and additive: it does NOTHING unless the triggering
    # message is INBOUND and the card has an ACTIVE ai_followup cadence. Manual
    # follow-ups, stage-automation follow-ups and the sync/AI-evaluation flow are
    # never touched.
    class AutoFollowupCanceler
      OPT_OUT_KEYWORDS = %w[stop sair parar cancelar descadastrar unsubscribe].freeze

      def initialize(card:, message: nil)
        @card = card
        @message = message
      end

      def maybe_cancel
        return unless @message&.incoming?
        return unless cadence_active?

        cancel_pending_follow_ups
        opted_out = opt_out?(@message)
        reason = opted_out ? 'opt_out' : 'replied'
        write_state(reason, opted_out)
        log_stopped(reason)
      end

      private

      def cadence_active?
        state['active'] == true
      end

      def cancel_pending_follow_ups
        @card.follow_ups.active.find_each do |follow_up|
          next unless follow_up.metadata.to_h['source'] == 'ai_followup'

          follow_up.update!(status: :canceled)
        end
      end

      def opt_out?(message)
        body = message&.content.to_s.downcase.strip
        return false if body.blank?

        OPT_OUT_KEYWORDS.include?(body)
      end

      def state
        (@card.metadata || {}).fetch('ai', {}).to_h.fetch('auto_followup_state', {}).to_h
      end

      def write_state(reason, opted_out)
        metadata = (@card.metadata || {}).deep_dup
        metadata['ai'] ||= {}
        metadata['ai']['auto_followup_state'] = state.merge(
          'active' => false,
          'stopped_reason' => reason,
          'opted_out' => opted_out,
          'next_due_at' => nil
        )
        @card.update!(metadata: metadata)
      end

      def log_stopped(reason)
        Crm::ActivityLogger.new(
          card: @card,
          actor: nil,
          event_type: 'ai_followup_stopped',
          conversation: @card.primary_conversation,
          payload: { reason: reason, trigger: 'inbound_reply', message_id: @message&.id }
        ).perform
      end
    end
  end
end
