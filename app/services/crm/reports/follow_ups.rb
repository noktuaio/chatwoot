module Crm
  module Reports
    # Follow-up health snapshot: counts by status plus overdue (pending and past
    # due) and due-soon (pending within the next 48h). Account-wide, optionally
    # narrowed to the selected pipeline's cards.
    class FollowUps < BaseReport
      DUE_SOON_WINDOW = 48.hours

      def perform
        by_status = Crm::FollowUp.statuses.transform_values { |value| status_counts[value] || 0 }

        {
          by_status: by_status,
          overdue: overdue_scope.count,
          due_soon: due_soon_scope.count
        }
      end

      private

      def base_scope
        scope = account.crm_follow_ups
        return scope if pipeline.blank?

        scope.where(card_id: account.crm_cards.where(pipeline_id: pipeline.id).select(:id))
      end

      def status_counts
        @status_counts ||= base_scope.group(:status).count
      end

      def pending_scope
        base_scope.where(status: Crm::FollowUp.statuses[:pending])
      end

      def overdue_scope
        pending_scope.where(due_at: ...Time.current)
      end

      def due_soon_scope
        pending_scope.where(due_at: Time.current..(Time.current + DUE_SOON_WINDOW))
      end
    end
  end
end
