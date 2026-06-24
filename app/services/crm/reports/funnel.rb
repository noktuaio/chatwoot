module Crm
  module Reports
    # Snapshot of OPEN cards distributed across the stages of a single pipeline
    # (mandatory selector; default = is_default). Count + value by currency per
    # stage so different currencies are never summed together.
    class Funnel < BaseReport
      def perform
        return empty if pipeline.blank?

        stages = pipeline.stages.order(:position, :id).to_a
        counts = open_cards.group(:stage_id).count
        values = open_cards.group(:stage_id, :currency).sum(:value_cents)

        {
          pipeline: { id: pipeline.id, name: pipeline.name },
          stages: stages.map { |stage| stage_entry(stage, counts, values) }
        }
      end

      private

      def empty
        { pipeline: nil, stages: [] }
      end

      def open_cards
        account.crm_cards.where(pipeline_id: pipeline.id, status: Crm::Card.statuses[:open])
      end

      def stage_entry(stage, counts, values)
        currency_values = values.select { |(stage_id, _currency), _cents| stage_id == stage.id }
                                .map { |(_stage_id, currency), cents| { currency: currency, value_cents: cents } }
        {
          id: stage.id,
          name: stage.name,
          position: stage.position,
          color: stage.color,
          count: counts[stage.id] || 0,
          value_by_currency: currency_values
        }
      end
    end
  end
end
