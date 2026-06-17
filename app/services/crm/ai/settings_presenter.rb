module Crm
  module Ai
    class SettingsPresenter
      def initialize(pipeline:)
        @pipeline = pipeline
      end

      def perform
        {
          enabled: pipeline_settings[:enabled] != false,
          auto_move_enabled: pipeline_settings[:auto_move_enabled] == true,
          stale_hours: pipeline_settings[:stale_hours].presence || Config::DEFAULT_STALE_HOURS,
          auto_followup: Config.auto_followup_settings(@pipeline),
          stages: @pipeline.stages.order(:position, :id).map do |stage|
            {
              id: stage.id,
              name: stage.name,
              ai_criteria: Config.stage_ai_criteria(stage),
              handoff: Config.handoff_settings(stage, @pipeline)
            }
          end
        }
      end

      private

      def pipeline_settings
        Config.pipeline_ai_settings(@pipeline)
      end
    end
  end
end
