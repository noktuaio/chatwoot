module Crm
  module Reports
    # Headline KPIs for the selected pipeline over the period: won/lost counts
    # (via closed_at), won value by currency, open pipeline value by currency,
    # and win rate. Currencies are never summed together.
    class Summary < BaseReport
      def perform
        return empty if pipeline.blank?

        won = closed_in_range.where(status: Crm::Card.statuses[:won])
        lost = closed_in_range.where(status: Crm::Card.statuses[:lost])
        won_count = won.count
        lost_count = lost.count
        decided = won_count + lost_count

        {
          pipeline: { id: pipeline.id, name: pipeline.name },
          period: { since: since.iso8601, until: until_time.iso8601 },
          won_count: won_count,
          lost_count: lost_count,
          win_rate: decided.zero? ? nil : (won_count.to_f / decided).round(4),
          win_rate_by_value: win_rate_by_value(won, lost),
          won_value_by_currency: currency_amount(won),
          lost_value_by_currency: currency_amount(lost),
          open_count: open_cards.count,
          open_value_by_currency: currency_amount(open_cards),
          goal: goal_payload
        }
      end

      private

      def empty
        { pipeline: nil }
      end

      def pipeline_cards
        account.crm_cards.where(pipeline_id: pipeline.id)
      end

      def open_cards
        pipeline_cards.where(status: Crm::Card.statuses[:open])
      end

      def closed_in_range
        pipeline_cards.where(closed_at: range)
      end

      # Value-weighted win rate = won_value / (won_value + lost_value). This is a
      # dimensionless ratio, so we sum value_cents across currencies for the
      # headline number (the per-currency money totals stay split elsewhere).
      def win_rate_by_value(won, lost)
        won_value = won.sum(:value_cents)
        lost_value = lost.sum(:value_cents)
        decided_value = won_value + lost_value
        return if decided_value.zero?

        (won_value.to_f / decided_value).round(4)
      end

      # Sales target attainment for the CURRENT month (a quota is monthly,
      # independent of the dashboard period selector). Returns nil when no goal
      # is set. `month_elapsed` powers the pacing indicator (attainment vs time).
      def goal_payload
        config = (pipeline.metadata || {})['goals']
        return if config.blank?

        target = config['monthly_target_cents'].to_i
        return if target.zero?

        currency = config['currency'].presence || 'BRL'
        month_start = Time.current.beginning_of_month
        achieved = pipeline_cards.where(status: Crm::Card.statuses[:won])
                                 .where(currency: currency)
                                 .where(closed_at: month_start..Time.current)
                                 .sum(:value_cents)
        month_span = Time.current.end_of_month - month_start

        {
          target_cents: target,
          currency: currency,
          achieved_cents: achieved,
          attainment: (achieved.to_f / target).round(4),
          month_elapsed: month_span.zero? ? 0 : ((Time.current - month_start) / month_span).round(4),
          month_label: month_start.strftime('%m/%Y')
        }
      end
    end
  end
end
