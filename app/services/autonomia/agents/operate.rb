module Autonomia
  module Agents
    # Namespace-módulo da camada "Operar" (Fase C/D). Coexiste com o diretório
    # homônimo app/services/autonomia/agents/operate/*.rb (Zeitwerk: módulo +
    # diretório de mesmo nome). Centraliza o predicado canônico "agente nativo
    # ATIVO nesta conversa?" e a lista de estratégias de handoff (Fase D), fonte
    # única consumida pelo FOLLOWUP_GUARD (AutoFollowupPlanner) e pelo HANDOFF.
    module Operate
      # Estratégias de reatribuição configuráveis por agente (jsonb config do Agent,
      # via store_accessor :handoff_strategy). Default conservador = 'none'.
      HANDOFF_STRATEGIES = %w[none inbox_member assign_member assign_team].freeze

      # Esta conversa está sendo atendida AGORA por um agente nativo ativo?
      #
      # Mesmo gate da Fase C (ReplyJob#eligible_agent_inbox / Responder#still_eligible?):
      #   pending  +  unassigned  +  AgentInbox do inbox  +  agent.enabled? && agent.active?
      #
      # Após o handoff (humano assume) a conversa deixa de ser pending e/ou ganha
      # assignee -> retorna false -> os consumidores (ex.: auto-followup) voltam ao
      # comportamento normal. Predicado puro/idempotente, sem efeitos colaterais.
      def self.active_for?(conversation)
        return false if conversation.blank?
        return false unless conversation.pending?
        return false if conversation.assignee_id.present?

        agent_inbox = ::Autonomia::Agents::AgentInbox.find_by(inbox_id: conversation.inbox_id)
        return false if agent_inbox.nil?

        agent = agent_inbox.agent
        agent&.enabled? && agent&.active? ? true : false
      end
    end
  end
end
