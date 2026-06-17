module Crm
  module Reports
    # How much of the stage movement is driven by AI vs humans, derived from the
    # authoritative crm_ai_stage_suggestions.status (never reconstructed from
    # move JSON). Scoped to the period by suggestion created_at.
    #
    #   auto_applied -> AI moved the card automatically
    #   accepted     -> human accepted an AI suggestion
    #   dismissed    -> human rejected an AI suggestion
    #   pending      -> awaiting a human decision
    #   expired      -> suggestion went stale
    class AiVsHuman < BaseReport
      def perform
        counts = suggestions.group(:status).count
        by_status = Crm::AiStageSuggestion.statuses.transform_values { |value| counts[value] || 0 }

        auto = by_status['auto_applied']
        accepted = by_status['accepted']
        dismissed = by_status['dismissed']
        ai_influenced = auto + accepted

        {
          period: { since: since.iso8601, until: until_time.iso8601 },
          by_status: by_status,
          ai_auto_moves: auto,
          ai_accepted: accepted,
          ai_dismissed: dismissed,
          ai_influenced_total: ai_influenced,
          acceptance_rate: (accepted + dismissed).zero? ? nil : (accepted.to_f / (accepted + dismissed)).round(4)
        }
      end

      private

      def suggestions
        scope = account.crm_ai_stage_suggestions.where(created_at: range)
        return scope if pipeline.blank?

        scope.where(card_id: account.crm_cards.where(pipeline_id: pipeline.id).select(:id))
      end
    end
  end
end
