module Autonomia
  module Agents
    module Operate
      # Fase D — resolve o ALVO humano do handoff de um agente nativo conforme a
      # estratégia configurada no agente (store_accessor :handoff_strategy / :handoff_target_id).
      #
      # Retorna User | Team | nil. nil = NÃO reatribui (estratégia 'none', alvo inválido
      # ou erro) -> o chamador (HandoffHandler) mantém o comportamento da Fase C: conversa
      # fica unassigned e o humano pega na fila. NUNCA levanta exceção (rede de segurança):
      # qualquer erro vira nil para não bloquear o bot_handoff!.
      #
      # REÚSO: estratégia inbox_member delega a seleção (round-robin/online) ao
      # Crm::Ai::HandoffMemberSelector — mesma lógica do Kanban, sem duplicar round-robin.
      class HandoffAssigner
        def initialize(conversation:, agent_inbox:)
          @conversation = conversation
          @agent_inbox = agent_inbox
          @agent = agent_inbox.agent
        end

        def perform
          strategy = @agent.handoff_strategy.presence || 'none'
          return nil if strategy == 'none'
          return nil unless HANDOFF_STRATEGIES.include?(strategy)

          case strategy
          when 'inbox_member'  then select_inbox_member
          when 'assign_member' then resolve_member
          when 'assign_team'   then resolve_team
          end
        rescue StandardError
          # Alvo inválido / erro inesperado -> unassigned (fila). NUNCA propaga.
          Rails.logger.warn("[autonomia][operate] handoff_assign_failed agent=#{@agent&.id}")
          nil
        end

        private

        # Round-robin entre membros do inbox, preferindo online (reusa o seletor do Kanban).
        def select_inbox_member
          inbox = @conversation.inbox
          return nil if inbox.blank?

          Crm::Ai::HandoffMemberSelector.new(
            inbox: inbox,
            account_id: @conversation.account_id,
            mode: 'round_robin',
            prefer_online: true
          ).perform
        end

        # User explícito — só se for membro válido do inbox (senão nil -> unassigned).
        def resolve_member
          target_id = @agent.handoff_target_id
          return nil if target_id.blank?

          @conversation.inbox.members.find_by(id: target_id)
        end

        # Team explícito da conta (senão nil -> unassigned).
        def resolve_team
          target_id = @agent.handoff_target_id
          return nil if target_id.blank?

          @conversation.account.teams.find_by(id: target_id)
        end
      end
    end
  end
end
