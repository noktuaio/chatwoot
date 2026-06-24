module Autonomia
  module Agents
    module Operate
      # CHANNEL-AGNÓSTICO (Onda 2b): materializa uma reação (emoji) como UMA mensagem incoming sintética
      # ("[O cliente reagiu com 👍 à sua última mensagem: \"...\"]") para o agente interpretar. Usado pelo
      # WhatsApp (Whatsapp::IncomingMessageBaseService — cobre Cloud oficial) e pelo Instagram
      # (Webhooks::InstagramEventsJob). Reúne a regra de segurança/zero-regressão num só lugar:
      #
      #   - SÓ materializa quando há ÂNCORA SEGURA: a msg reagida existe NESTE inbox (scope `.chat` =
      #     exclui privadas/activities) E a conversa-alvo passa em Operate.eligible_agent_inbox (agente
      #     ativo/não-interno/não-sistema, sem responsável humano, allowlist, feature on).
      #   - NÃO resolve contato pelo payload: usa `conversation.contact` (no 1:1 = quem reagiu) -> ZERO
      #     side-effect (sem criar/atualizar Contact/ContactInbox nem webhook de contato) no descarte.
      #   - Dedup idempotente pelo `event_source_id`. Guarda de concorrência opcional (`lock:`) chamada só
      #     ANTES do create (após as validações) -> descarte não deixa lock residual.
      #   - Fail-safe: qualquer erro -> nil (cai no descarte normal do canal). NUNCA cria conversa nova.
      class ReactionMaterializer
        def self.call(**kwargs)
          new(**kwargs).call
        end

        # lock: proc opcional retornando truthy se adquiriu a trava de concorrência do canal (ex.: o
        # MessageDedupLock do WhatsApp). Sem lock, confia no dedup por source_id + mutex do canal.
        def initialize(inbox:, reacted_source_id:, emoji:, event_source_id:, lock: nil)
          @inbox = inbox
          @reacted_source_id = reacted_source_id.to_s
          @emoji = emoji.to_s.strip
          @event_source_id = event_source_id.to_s
          @lock = lock
        end

        # -> Message criada, ou nil (descartado).
        def call
          return if @emoji.blank? || @reacted_source_id.blank? || @event_source_id.blank?

          reacted = ::Message.where(inbox_id: @inbox.id).chat.find_by(source_id: @reacted_source_id)
          conversation = reacted&.conversation
          return if conversation.nil?

          contact = conversation.contact
          return if contact.nil? || contact.blocked?

          agent_inbox = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation)
          return if agent_inbox.blank?
          return unless ::Autonomia::Agents::Config.operate_reactions_enabled?(agent_inbox.agent) # gate por-agente

          return if conversation.messages.find_by(source_id: @event_source_id) # dedup idempotente
          return if @lock && !@lock.call                                       # concorrência só ao materializar

          conversation.messages.create!(
            content: content_for(reacted),
            account_id: @inbox.account_id,
            inbox_id: @inbox.id,
            message_type: :incoming,
            status: :sent,
            sender: contact,
            source_id: @event_source_id,
            content_attributes: { autonomia_reaction: { emoji: @emoji, reacted_source_id: @reacted_source_id } }
          )
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] reaction_materialize_failed inbox=#{@inbox&.id} #{e.class}")
          nil
        end

        private

        def content_for(reacted)
          target = reacted.outgoing? ? 'à sua última mensagem' : 'a uma mensagem anterior dele'
          quoted = reacted.content.to_s.strip.tr("\n", ' ').first(160)
          base = "[O cliente reagiu com #{@emoji} #{target}"
          base += ": \"#{quoted}\"" if quoted.present?
          "#{base}]"
        end
      end
    end
  end
end
