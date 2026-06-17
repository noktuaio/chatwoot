module Crm
  module Reports
    # Cards closed (won/lost) over time, bucketed by day/week/month, for the
    # selected pipeline. Drives the throughput timeseries chart.
    class Throughput < BaseReport
      BUCKETS = { 'day' => 'day', 'week' => 'week', 'month' => 'month' }.freeze

      def perform
        won = bucketed(closed_in_range.where(status: Crm::Card.statuses[:won]))
        lost = bucketed(closed_in_range.where(status: Crm::Card.statuses[:lost]))
        keys = (won.keys + lost.keys).uniq.sort

        {
          group_by: bucket,
          period: { since: since.iso8601, until: until_time.iso8601 },
          series: keys.map do |key|
            { date: key.to_date.iso8601, won: won[key] || 0, lost: lost[key] || 0 }
          end
        }
      end

      private

      def bucket
        BUCKETS[params[:group_by].to_s] || 'day'
      end

      def closed_in_range
        scope = account.crm_cards.where(closed_at: range)
        pipeline.present? ? scope.where(pipeline_id: pipeline.id) : scope
      end

      def bucketed(scope)
        scope.group(Arel.sql("date_trunc('#{bucket}', closed_at)")).count
      end
    end
  end
end
