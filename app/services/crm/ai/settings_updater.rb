module Crm
  module Ai
    class SettingsUpdater
      def initialize(pipeline:, params:, stage_criteria: {}, stage_handoff: {})
        @pipeline = pipeline
        @params = params.to_h.with_indifferent_access
        @stage_criteria = stage_criteria.to_h
        @stage_handoff = stage_handoff.to_h
      end

      def perform
        update_pipeline_metadata!
        update_stage_metadata!
        @pipeline
      end

      private

      def update_pipeline_metadata!
        metadata = (@pipeline.metadata || {}).deep_dup
        ai = (metadata['ai'] || {}).merge(
          'enabled' => cast_boolean(@params[:enabled], default: true),
          'auto_move_enabled' => cast_boolean(@params[:auto_move_enabled], default: false),
          'stale_hours' => (@params[:stale_hours].presence || Config::DEFAULT_STALE_HOURS).to_i
        )
        # Partial saves must not clobber an existing auto_followup config.
        ai['auto_followup'] = normalize_auto_followup(@params[:auto_followup]) if @params.key?(:auto_followup)
        metadata['ai'] = ai
        @pipeline.update!(metadata: metadata)
      end

      def normalize_auto_followup(params)
        cfg = params.to_h.with_indifferent_access
        {
          'enabled' => cast_boolean(cfg[:enabled], default: false),
          'trigger_idle_hours' => cfg[:trigger_idle_hours].to_i,
          'max_touches' => cfg[:max_touches].to_i,
          'intervals_hours' => Array(cfg[:intervals_hours]).map(&:to_i),
          'quiet_hours' => normalize_quiet_hours(cfg[:quiet_hours]),
          'tone_instructions' => cfg[:tone_instructions].to_s.strip
        }
      end

      def normalize_quiet_hours(params)
        cfg = params.to_h.with_indifferent_access
        {
          'start' => cfg[:start].to_i,
          'end' => cfg[:end].to_i,
          'tz' => cfg[:tz].to_s.strip.presence || 'contact'
        }
      end

      def update_stage_metadata!
        return if @stage_criteria.blank? && @stage_handoff.blank?

        @pipeline.stages.find_each do |stage|
          key = stage.id.to_s
          criteria = @stage_criteria[key]
          handoff = @stage_handoff[key]
          next if criteria.nil? && handoff.nil?

          metadata = (stage.metadata || {}).deep_dup
          metadata['ai_criteria'] = criteria.to_s.strip unless criteria.nil?
          metadata['ai_handoff'] = normalize_handoff(handoff) unless handoff.nil?
          stage.update!(metadata: metadata)
        end
      end

      def normalize_handoff(handoff)
        cfg = handoff.to_h.with_indifferent_access
        mode = Config::HANDOFF_MODES.include?(cfg[:mode]) ? cfg[:mode] : 'round_robin'
        {
          'enabled' => cast_boolean(cfg[:enabled], default: false),
          'mode' => mode,
          'trigger' => cfg[:trigger].to_s.strip,
          'prefer_online' => cast_boolean(cfg[:prefer_online], default: true)
        }
      end

      def cast_boolean(value, default:)
        return default if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
