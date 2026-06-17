module Crm
  module Ai
    class Config
      BOOLEAN = ActiveModel::Type::Boolean.new

      AUTO_MOVE_THRESHOLD = 0.75
      SUGGESTION_THRESHOLD = 0.55
      DEBOUNCE_SECONDS = 15
      MIN_EVALUATION_INTERVAL_SECONDS = 30
      AUTO_MOVE_COOLDOWN_SECONDS = DEBOUNCE_SECONDS
      DEFAULT_STALE_HOURS = 48

      MODEL_SUMMARY = 'gpt-5.4-mini'.freeze
      MODEL_CLASSIFY = 'gpt-5.4-mini'.freeze
      MODEL_AUTO_MOVE = 'gpt-5.4'.freeze
      MODEL_FOLLOWUP = 'gpt-5.4-mini'.freeze
      # E-mail builder copilot (multimodal generate). Full model — sees images/PDFs and writes MJML.
      MODEL_EMAIL = 'gpt-5.4'.freeze
      # Per-PDF byte cap and per-request PDF count cap for the e-mail copilot (guards download/base64
      # of attached PDFs before they become input_file content parts).
      PDF_BYTE_LIMIT = 32_000_000
      MAX_PDFS_PER_REQUEST = 5

      # AI auto follow-up ("de onde parou") MVP tuning.
      FOLLOWUP_MIN_CONFIDENCE = 0.6
      AUTO_FOLLOWUP_SCAN_CRON_MINUTES = 15
      AUTO_FOLLOWUP_TEMPLATE_CAP_HOURS = 24

      DEFAULT_AUTO_FOLLOWUP = {
        'enabled' => false,
        'trigger_idle_hours' => 6,
        'max_touches' => 3,
        'intervals_hours' => [20, 72, 168],
        'quiet_hours' => { 'start' => 8, 'end' => 20, 'tz' => 'contact' },
        'tone_instructions' => ''
      }.freeze

      # Media enrichment (PR13.1): audio via transcription, image via vision caption.
      TRANSCRIBE_MODEL = 'gpt-4o-mini-transcribe'.freeze
      VISION_MODEL = 'gpt-5.4-mini'.freeze
      TRANSCRIPTION_BYTE_LIMIT = 25_000_000
      IMAGE_BYTE_LIMIT = 18_000_000
      MAX_MEDIA_ENRICH_PER_EVAL = 12
      TRANSCRIPT_MAX_CHARS = 1500
      CAPTION_MAX_CHARS = 400

      def self.enabled?
        ::Crm::Config.enabled? && BOOLEAN.cast(ENV.fetch('CRM_AI_ENABLED', false))
      end

      def self.media_enabled?
        enabled? && BOOLEAN.cast(ENV.fetch('CRM_AI_MEDIA_ENABLED', true))
      end

      def self.pipeline_ai_settings(pipeline)
        (pipeline.metadata || {}).fetch('ai', {}).to_h.with_indifferent_access
      end

      def self.stage_ai_criteria(stage)
        (stage.metadata || {}).fetch('ai_criteria', '').to_s.strip
      end

      # Effective AI auto follow-up config for a pipeline. Pipeline-level
      # metadata.ai.auto_followup overrides the defaults; +enabled+ is always
      # cast to a real boolean so the planner/runner/scan-job can branch safely.
      def self.auto_followup_settings(pipeline)
        cfg = DEFAULT_AUTO_FOLLOWUP.merge(pipeline_ai_settings(pipeline).fetch('auto_followup', {}).to_h)
        cfg['enabled'] = BOOLEAN.cast(cfg['enabled'])
        cfg.with_indifferent_access
      end

      # Don't re-hand-off the same conversation within this window (loop/spam guard).
      HANDOFF_COOLDOWN_SECONDS = 6 * 60 * 60
      HANDOFF_MODES = %w[direct round_robin].freeze

      # Effective handoff config for a card's current stage. Stage-level config
      # overrides pipeline-level defaults so a funnel can set a baseline and a
      # stage can refine it.
      def self.handoff_settings(stage, pipeline)
        pipeline_cfg = pipeline_ai_settings(pipeline).fetch('handoff', {}).to_h
        stage_cfg = (stage&.metadata || {}).fetch('ai_handoff', {}).to_h
        cfg = pipeline_cfg.merge(stage_cfg)
        {
          enabled: BOOLEAN.cast(cfg['enabled']),
          mode: HANDOFF_MODES.include?(cfg['mode']) ? cfg['mode'] : 'round_robin',
          trigger: cfg['trigger'].to_s.strip,
          prefer_online: cfg.key?('prefer_online') ? BOOLEAN.cast(cfg['prefer_online']) : true
        }.with_indifferent_access
      end
    end
  end
end
