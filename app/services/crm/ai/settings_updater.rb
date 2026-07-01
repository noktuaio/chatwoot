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
        ai = metadata['ai'] || {}
        # Merge PARCIAL por chave: só sobrescreve o que veio nos params. Permite que o atalho do
        # calendário envie SÓ callback_enabled sem zerar enabled/auto_move/stale (o painel do funil
        # segue mandando tudo, sem regressão). Espelha a salvaguarda que já existia p/ auto_followup.
        ai['enabled'] = cast_boolean(@params[:enabled], default: true) if @params.key?(:enabled)
        ai['auto_move_enabled'] = cast_boolean(@params[:auto_move_enabled], default: false) if @params.key?(:auto_move_enabled)
        ai['callback_enabled'] = cast_boolean(@params[:callback_enabled], default: true) if @params.key?(:callback_enabled)
        ai['callback_mode'] = normalize_callback_mode(@params[:callback_mode]) if @params.key?(:callback_mode)
        ai['stale_hours'] = (@params[:stale_hours].presence || Config::DEFAULT_STALE_HOURS).to_i if @params.key?(:stale_hours)
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
          metadata['ai_handoff'] = normalize_handoff(handoff, metadata['ai_handoff']) unless handoff.nil?
          stage.update!(metadata: metadata)
        end
      end

      # Merge PARCIAL por chave sobre o bloco já gravado: só sobrescreve o que veio no params.
      # Assim o save do painel (que ainda NÃO expõe handoff_mode) não reverte um override
      # r3_invite ligado por outro caminho, e um PATCH parcial não apaga os demais campos.
      # Chaves ausentes no blob antigo caem nos defaults seguros (mesma resolução da leitura).
      def normalize_handoff(handoff, existing = {})
        cfg = handoff.to_h.with_indifferent_access
        result = normalized_handoff_defaults(existing)
        result['enabled'] = cast_boolean(cfg[:enabled], default: false) if cfg.key?(:enabled)
        result['mode'] = normalize_handoff_selector(cfg[:mode]) if cfg.key?(:mode)
        result['handoff_mode'] = normalize_handoff_flow(cfg[:handoff_mode]) if cfg.key?(:handoff_mode)
        result['trigger'] = cfg[:trigger].to_s.strip if cfg.key?(:trigger)
        result['prefer_online'] = cast_boolean(cfg[:prefer_online], default: true) if cfg.key?(:prefer_online)
        result
      end

      def normalized_handoff_defaults(existing)
        cfg = (existing || {}).to_h.with_indifferent_access
        {
          'enabled' => cast_boolean(cfg[:enabled], default: false),
          'mode' => normalize_handoff_selector(cfg[:mode]),
          'handoff_mode' => normalize_handoff_flow(cfg[:handoff_mode]),
          'trigger' => cfg[:trigger].to_s.strip,
          'prefer_online' => cfg.key?(:prefer_online) ? cast_boolean(cfg[:prefer_online], default: true) : true
        }
      end

      def normalize_handoff_selector(value)
        Config::HANDOFF_MODES.include?(value) ? value : 'round_robin'
      end

      def normalize_handoff_flow(value)
        Config::HANDOFF_FLOW_MODES.include?(value) ? value : 'r2_direct'
      end

      def cast_boolean(value, default:)
        return default if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end

      def normalize_callback_mode(value)
        mode = value.to_s
        Config::CALLBACK_MODES.include?(mode) ? mode : 'reminder'
      end
    end
  end
end
