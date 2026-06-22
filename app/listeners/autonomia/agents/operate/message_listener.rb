module Autonomia
  module Agents
    module Operate
      # Fase C "Operar" — ouve `message.created` e dispara a resposta do agente
      # nativo. ESPELHA o mecanismo do CRM (`Crm::ConversationObserverListener`):
      # herda de BaseListener (Singleton), registra-se no array `listeners` do
      # AsyncDispatcher (Sidekiq), e SÓ enfileira um job — toda decisão cara
      # (DB/estado/IA) vive no ReplyJob.
      #
      # ANTI-LOOP / ZERO REGRESSÃO: este listener só age para mensagens INCOMING,
      # públicas (não private) e não-activity, com a feature flag ligada. A
      # resposta OUTGOING do próprio bot (sender AgentBot) NUNCA é incoming, logo
      # nunca re-dispara o processamento. Em qualquer outro caso: no-op silencioso
      # e barato (sem tocar o core de mensagens).
      class MessageListener < BaseListener
        def message_created(event)
          message = event.data[:message]
          return if ignored?(message)
          return if ::Autonomia::Channels::BroadcastGuard.blocked_conversation?(message.conversation)

          # Gate POR CONTA: ENV master + feature `autonomia_agents` da conta DESTA
          # mensagem (rodamos fora de request, sem Current.account). message.account
          # é o caminho canônico do core; a conta certa é a dona da conversa/inbox.
          return unless ::Autonomia::Agents::Config.enabled?(message.account)

          # vínculo (AgentInbox) + agent.enabled?/active? + conversa pending +
          # unassigned são checados no Job (precisam de DB). Aqui só o mínimo barato.
          ::Autonomia::Agents::Operate::ReplyJob.perform_later(message.conversation_id, message.id)
        end

        private

        def ignored?(message)
          message.blank? ||
            !message.incoming? ||      # ANTI-LOOP: só mensagens do contato disparam
            message.private? ||        # nunca processa notas privadas
            message.activity? ||       # eventos de atividade não são respondíveis
            message.conversation_id.blank?
        end
      end
    end
  end
end
