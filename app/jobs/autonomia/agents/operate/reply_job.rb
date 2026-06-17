module Autonomia
  module Agents
    module Operate
      # Fase C "Operar" — DEBOUNCE. Coalesce a rajada de mensagens do contato (várias
      # linhas seguidas) em UMA resposta sobre o contexto mais recente, via token-guard
      # com `additional_attributes['autonomia_debounce']` + re-enqueue (last-writer-wins).
      #
      # Mecanismo (2 fases, mesmo job):
      #   - 'trigger' (disparado pelo MessageListener a cada incoming): roda os guards de
      #     estado; grava o stamp com o `pending_message_id` desta mensagem; reagenda a si
      #     mesmo com wait = OPERATE_DEBOUNCE_SECONDS na fase 'settle'.
      #   - 'settle' (após a janela): relê o stamp. Se o `pending_message_id` NÃO bate mais
      #     com este `message_id`, uma mensagem mais nova chegou e já reagendou -> ABORTA
      #     (idempotente). Se ainda bate, chama o Responder UMA vez.
      #
      # ZERO REGRESSÃO / ANTI-LOOP: toda decisão cara (DB/estado/IA) vive aqui, não no
      # listener. No-op barato e silencioso se a conversa não estiver elegível. O stamp é
      # gravado com `update_column` (sem callbacks) -> NUNCA re-dispara MESSAGE_CREATED nem
      # observers. A resposta outgoing do bot não é incoming, logo nunca volta a este job.
      class ReplyJob < ApplicationJob
        queue_as :low

        DEBOUNCE_KEY = 'autonomia_debounce'.freeze

        def perform(conversation_id, message_id, phase = 'trigger')
          conversation = Conversation.find_by(id: conversation_id)
          return if conversation.blank?

          # Gate POR CONTA: ENV master + feature da conta DONA da conversa. Job roda
          # fora de request (sem Current.account); a conta certa é conversation.account.
          # Re-checado aqui (e não só no listener) porque a feature pode ter sido
          # desligada na janela entre o enqueue e a execução -> para de responder.
          return unless ::Autonomia::Agents::Config.enabled?(conversation.account)

          agent_inbox = eligible_agent_inbox(conversation)
          return if agent_inbox.blank?

          phase == 'settle' ? settle(conversation, agent_inbox, message_id) : trigger(conversation, agent_inbox, message_id)
        end

        private

        # Guards de estado (espelham sec.2/3 da spec): inbox vinculado a um AgentInbox de
        # agente ATIVO, conversa PENDING (bot no comando) e UNASSIGNED (nenhum humano).
        # Qualquer falha -> nil -> no-op. Não toca o core de mensagens.
        def eligible_agent_inbox(conversation)
          return unless conversation.pending?
          return if conversation.assignee_id.present?

          agent_inbox = ::Autonomia::Agents::AgentInbox.find_by(inbox_id: conversation.inbox_id)
          return if agent_inbox.blank?
          # kill-switch em runtime: `enabled` (boolean) é independente do `status` (enum).
          # Se o admin desliga o agente com o inbox já vinculado, o bot PARA de responder.
          return unless agent_inbox.agent&.enabled? && agent_inbox.agent&.active?

          agent_inbox
        end

        # Fase 'trigger': grava o stamp (last-writer-wins) e agenda o settle. Cada incoming
        # nova sobrescreve `pending_message_id` e reagenda; só o último settle prossegue.
        # Janela CONFIGURÁVEL por agente (config['debounce_seconds']), default OPERATE_DEBOUNCE_SECONDS.
        def trigger(conversation, agent_inbox, message_id)
          stamp_debounce(conversation, message_id)
          self.class.set(wait: ::Autonomia::Agents::Config.debounce_seconds_for(agent_inbox.agent))
              .perform_later(conversation.id, message_id, 'settle')
        end

        # Fase 'settle': só prossegue se este ainda é o último trigger da janela.
        def settle(conversation, agent_inbox, message_id)
          return unless current_token?(conversation, message_id)

          ::Autonomia::Agents::Operate::Responder.new(
            conversation: conversation,
            agent_inbox: agent_inbox,
            reply_to_message_id: message_id
          ).perform
        end

        # Grava SÓ a chave do debounce via jsonb_set no servidor (merge per-chave, não
        # overwrite do blob): preserva chaves escritas concorrentemente por outros writers
        # async na mesma conversa (ex.: automation_rule_listener, conversation_language).
        # update_all -> SEM callbacks/validations -> não dispara MESSAGE_CREATED/observers
        # (anti-loop) e é barato. Sobrescrever a coluna inteira com uma cópia stale
        # apagaria essas chaves (perda de dados concorrente).
        def stamp_debounce(conversation, message_id)
          stamp = { 'pending_message_id' => message_id, 'at' => Time.current.to_f }
          Conversation.where(id: conversation.id).update_all(
            [
              "additional_attributes = jsonb_set(COALESCE(additional_attributes, '{}'::jsonb), " \
              "ARRAY[?], ?::jsonb, true)",
              DEBOUNCE_KEY, stamp.to_json
            ]
          )
        end

        # Relê o stamp do banco e compara o token. Mensagem mais nova => token diferente => aborta.
        def current_token?(conversation, message_id)
          conversation.reload.additional_attributes
                      .to_h.dig(DEBOUNCE_KEY, 'pending_message_id') == message_id
        end
      end
    end
  end
end
