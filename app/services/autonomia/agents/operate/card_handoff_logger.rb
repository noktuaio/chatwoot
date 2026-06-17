module Autonomia
  module Agents
    module Operate
      # Fase D — [CARD]. Registro OPCIONAL e BEST-EFFORT do motivo do handoff do agente
      # nativo no card/timeline do Kanban, REUSANDO o mecanismo existente do CRM
      # (Crm::ActivityLogger -> Crm::Activity). NÃO duplica lógica de timeline.
      #
      # Chamado pelo HandoffHandler (área HANDOFF) DEPOIS de reatribuir o atendimento ao
      # humano (assign_human!). Guardado por Crm::Config.enabled? + card presente:
      #   - CRM desligado  -> no-op (conversas sem Kanban não são afetadas);
      #   - conversa sem card -> no-op (nada a registrar);
      #   - qualquer erro -> engolido (registro nunca bloqueia/derruba o handoff).
      #
      # IP OCULTO: o payload carrega APENAS ids/strategy (agent_id, strategy, assignee_id,
      # team_id). O motivo bruto do LLM, instruction, scaffold e prompt NUNCA entram aqui —
      # e como Crm::Activity#emit_webhook_event repassa event_type+payload ao webhook, manter
      # o payload livre de IP também protege o canal HTTP de saída.
      class CardHandoffLogger
        EVENT_TYPE = 'autonomia_handoff'.freeze

        # conversation: Conversation atendida pelo agente nativo
        # agent: Autonomia::Agents::Agent que estava no comando
        # target: User (assignee) | Team | nil (nil = ficou unassigned)
        def initialize(conversation:, agent:, target:)
          @conversation = conversation
          @agent = agent
          @target = target
        end

        def perform
          return unless crm_enabled?

          # Ordenação determinística: crm_cards é has_many sem order; .first
          # poderia variar entre execuções com múltiplos cards. order(:id) fixa o
          # card mais antigo (best-effort para o registro do motivo).
          card = @conversation&.crm_cards&.order(:id)&.first
          return if card.blank?

          Crm::ActivityLogger.new(
            card: card,
            actor: nil,
            event_type: EVENT_TYPE,
            conversation: @conversation,
            payload: handoff_payload
          ).perform
        rescue StandardError => e
          # Best-effort: o registro do motivo nunca pode bloquear o handoff.
          Rails.logger.warn("[autonomia][operate] card_handoff_log_skipped conv=#{@conversation&.id} #{e.class}")
          nil
        end

        private

        def crm_enabled?
          defined?(Crm::Config) && Crm::Config.enabled?
        end

        # Apenas ids/strategy — sem instruction/scaffold/prompt/motivo bruto do LLM.
        def handoff_payload
          team_target = @target.is_a?(Team)
          {
            agent_id: @agent&.id,
            strategy: @agent&.handoff_strategy.presence || 'none',
            assignee_id: team_target ? nil : @target&.id,
            team_id: team_target ? @target.id : nil
          }
        end
      end
    end
  end
end
