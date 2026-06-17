module Autonomia
  module Agents
    module Operate
      # ENTREGA HUMANIZADA — INDICADOR "DIGITANDO" por canal. Mostra/limpa o "digitando" do agente
      # durante as pausas entre os pedaços da resposta. Adaptador com DEGRADAÇÃO GRACIOSA: cada canal
      # usa o mecanismo que tem; canal sem suporte simplesmente não mostra typing (a entrega chunk+delay
      # continua). NUNCA levanta no caminho vivo (best-effort, rescue largo) — typing é cosmético.
      #
      #   - Web widget / API (chat ao vivo): NATIVO. Dispara CONVERSATION_TYPING_ON/OFF pelo dispatcher
      #     (mesmo caminho do TypingStatusManager); o widget do contato mostra a bolha "digitando".
      #   - WhatsApp Cloud oficial: chama a API da Meta (status:read + typing_indicator) referenciando o
      #     wamid da última mensagem do cliente — idêntico ao nó "WA API Oficial" do fluxo n8n. WhatsApp
      #     não tem "typing off": o indicador some sozinho (~25s) ou quando a mensagem chega → off vira no-op.
      #   - Instagram: sender_action typing_on/off (Graph). Best-effort; se a conta/permite não suportar,
      #     degrada silenciosamente.
      #   - Demais canais: no-op.
      class TypingIndicator
        include Events::Types

        def initialize(conversation:, agent_inbox:)
          @conversation = conversation
          @agent_inbox  = agent_inbox
          @channel = conversation.inbox&.channel
        end

        def on
          dispatch(true)
        end

        def off
          dispatch(false)
        end

        private

        def dispatch(typing_on)
          case @channel
          when Channel::WebWidget, Channel::Api
            web_widget_typing(typing_on)
          when Channel::Whatsapp
            whatsapp_typing(typing_on) if external_typing_enabled?
          when Channel::Instagram
            instagram_typing(typing_on) if external_typing_enabled?
          end
        rescue StandardError => e
          # Typing é cosmético: qualquer falha (rede/credencial/versão de API) NÃO pode quebrar a entrega.
          Rails.logger.warn("[autonomia][operate][typing] degraded conv=#{@conversation.id} #{e.class}")
          nil
        end

        def external_typing_enabled?
          ::Autonomia::Agents::Config.channel_typing_enabled?
        end

        # Web widget: emite o evento nativo do Chatwoot. O "user" é o AgentBot-espelho (tem
        # push_event_data); o ActionCableListener faz broadcast ao contato (token do contact_inbox).
        def web_widget_typing(typing_on)
          event = typing_on ? CONVERSATION_TYPING_ON : CONVERSATION_TYPING_OFF
          Rails.configuration.dispatcher.dispatch(
            event, Time.zone.now,
            conversation: @conversation, user: @agent_inbox.agent_bot, is_private: false
          )
        end

        # WhatsApp Cloud: typing só faz sentido "ligar" (a Meta limpa sozinha). Precisa do wamid da
        # última mensagem incoming do cliente; sem ela, no-op.
        def whatsapp_typing(typing_on)
          return unless typing_on
          return unless @channel.respond_to?(:provider) && @channel.provider == 'whatsapp_cloud'

          wamid = last_incoming_source_id
          return if wamid.blank?

          service = @channel.provider_service
          return unless service.respond_to?(:send_typing_indicator)

          service.send_typing_indicator(wamid)
        end

        # Instagram: sender_action typing_on/off para o id do contato.
        def instagram_typing(typing_on)
          recipient = @conversation.contact_inbox&.source_id
          return if recipient.blank?

          ::Instagram::SendOnInstagramService.new(message: latest_outgoing_or_incoming)
                                             .send_sender_action(recipient, typing_on ? 'typing_on' : 'typing_off')
        rescue NameError, NoMethodError
          nil # serviço/método ausente em algum build → degrada
        end

        def last_incoming_source_id
          @conversation.messages.incoming.where.not(source_id: [nil, '']).order(created_at: :desc).limit(1).pick(:source_id)
        end

        def latest_outgoing_or_incoming
          @conversation.messages.where.not(message_type: :activity).order(created_at: :desc).first
        end
      end
    end
  end
end
