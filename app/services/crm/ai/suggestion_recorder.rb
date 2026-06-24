module Crm
  module Ai
    class SuggestionRecorder
      def initialize(card:, from_stage:, to_stage:, confidence:, reasoning:, model_used:, status:, metadata: {})
        @card = card
        @from_stage = from_stage
        @to_stage = to_stage
        @confidence = confidence
        @reasoning = reasoning
        @model_used = model_used
        @status = status
        @metadata = metadata
      end

      def perform
        expire_pending_suggestions!
        create_suggestion!
      end

      private

      def expire_pending_suggestions!
        @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).find_each do |suggestion|
          suggestion.update!(status: :expired)
        end
      end

      def create_suggestion!
        suggestion = @card.account.crm_ai_stage_suggestions.create!(
          card: @card,
          from_stage: @from_stage,
          to_stage: @to_stage,
          confidence: @confidence,
          reasoning: @reasoning.to_s.truncate(500),
          model_used: @model_used,
          status: @status,
          metadata: @metadata
        )

        log_activity!(suggestion)
        suggestion
      end

      def log_activity!(suggestion)
        Crm::ActivityLogger.new(
          card: @card,
          actor: nil,
          event_type: suggestion.auto_applied? ? 'ai_auto_moved' : 'ai_suggested',
          payload: {
            suggestion_id: suggestion.id,
            from_stage_id: suggestion.from_stage_id,
            to_stage_id: suggestion.to_stage_id,
            confidence: suggestion.confidence.to_f
          }
        ).perform
      end
    end
  end
end
