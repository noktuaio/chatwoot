module Autonomia
  module Agents
    module Operate
      # Fase C "Operar" — RESPONDER. Chamado pelo ReplyJob (após o debounce) com a
      # conversa elegível (pending + unassigned + AgentInbox de agente ATIVO). Monta o
      # histórico das N últimas mensagens públicas, chama o motor de resposta da Fase B
      # (Autonomia::Agents::Answerer) e:
      #   - se houver reply e SEM handoff -> posta a resposta OUTGOING pelo caminho
      #     canônico canal-agnóstico (Messages::MessageBuilder com sender AgentBot espelho),
      #     idêntico ao Crm::FollowUps::MessageSender;
      #   - se reply em branco OU handoff.should -> delega ao HandoffHandler (mensagem
      #     graciosa + bot_handoff!).
      #
      # ANTI-LOOP: a mensagem postada é OUTGOING (sender AgentBot), logo NUNCA é incoming
      # e o MessageListener a ignora. ZERO REGRESSÃO: só age sobre a conversa já validada
      # pelo Job; nenhum guard de estado é reavaliado aqui.
      #
      # SEGURANÇA/IP: só o `reply`/`fallback_message` (texto destinado ao cliente) é
      # postado. NUNCA instruction/scaffold/prompt vai à mensagem, ao log ou ao
      # content_attributes — apenas o id do agente para rastreabilidade.
      class Responder
        Result = Struct.new(:status, :message, :error, keyword_init: true) do
          def self.replied(message)
            new(status: :replied, message: message)
          end

          def self.handed_off
            new(status: :handed_off)
          end

          def self.failed(error)
            new(status: :failed, error: error)
          end
        end

        def initialize(conversation:, agent_inbox:, reply_to_message_id: nil)
          @conversation = conversation
          @agent_inbox  = agent_inbox
          @agent        = agent_inbox.agent
          @reply_to_message_id = reply_to_message_id
        end

        # -> Result
        def perform
          # A chamada à IA (lenta) roda FORA do lock para não segurar a linha da conversa.
          result = answer
          return handoff(result) if handoff?(result)

          # ENTREGA HUMANIZADA (aditiva, kill-switch): quebra a resposta em pedaços com "digitando" +
          # pausa, entregues por um job encadeado. Quando OFF (ENV/por-agente) cai no caminho clássico
          # de 1 mensagem abaixo — ZERO mudança de comportamento.
          return deliver_humanized(result) if ::Autonomia::Agents::Config.humanize_delivery_enabled?(@agent)

          classic_deliver(result)
        rescue StandardError => e
          # Falha inesperada ao postar -> handoff seguro: melhor entregar ao humano
          # do que deixar o contato sem resposta. error code curto, sem eco de prompt.
          Rails.logger.warn("[autonomia][operate] responder_failed agent=#{@agent.id} conv=#{@conversation.id}")
          handoff(nil, error: e.class.name)
        end

        private

        # Caminho CLÁSSICO: 1 mensagem única (comportamento original, intocado). Usado quando a
        # humanização está OFF e como FALLBACK quando o quebrador não produz pedaço (resposta só com
        # caracteres invisíveis) — preserva paridade exata com o modo OFF.
        #
        # Lock por conversa só na hora de postar: reavalia elegibilidade com estado fresco (um humano
        # pode ter assumido durante a chamada à IA) e garante idempotência (retry do Sidekiq após post
        # não duplica). IMPORTANTE (Rails 7.1): NÃO usar return/break dentro do with_lock — dispararia
        # ROLLBACK e descartaria a mensagem recém-postada. Computa-se o Result numa variável.
        def classic_deliver(result)
          outcome = @conversation.with_lock do
            if !still_eligible?
              Result.handed_off
            elsif already_replied?
              Result.replied(nil)
            else
              Result.replied(post_reply!(result.reply))
            end
          end

          # Fase F (ADITIVO/best-effort): só registra quando uma resposta NOVA foi postada
          # (outcome.message presente — exclui already_replied?, que devolve message nil, e
          # o caso still_eligible?==false, que virou handoff). EventLogger nunca levanta.
          if outcome.status == :replied && outcome.message.present?
            ::Autonomia::Agents::Operate::EventLogger.replied(
              agent: @agent, conversation: @conversation, result: result
            )
          end
          outcome
        end

        # Inicia a entrega humanizada: quebra a resposta, mostra "digitando" e agenda o 1º pedaço.
        # Guardas baratas aqui (idempotência/elegibilidade); as AUTORITATIVAS (lock + token + por-chunk)
        # vivem no ChunkedDeliveryJob. NÃO posta nada de forma síncrona.
        def deliver_humanized(result)
          return Result.replied(nil) if already_replied?      # um settle anterior já entregou
          return Result.handed_off unless still_eligible?     # humano assumiu durante a IA -> não posta

          chunks = ::Autonomia::Agents::Operate::ReplyChunker.call(result.reply)
          # Nada a quebrar (ex.: resposta só com invisíveis) -> caminho clássico (paridade com OFF),
          # nunca engole a resposta silenciosamente.
          return classic_deliver(result) if chunks.empty?

          meta = { 'confidence' => result.confidence, 'answered_from_knowledge' => result.answered_from_knowledge }
          ::Autonomia::Agents::Operate::TypingIndicator.new(conversation: @conversation, agent_inbox: @agent_inbox).on
          ::Autonomia::Agents::Operate::ChunkedDeliveryJob
            .set(wait: (chunks.first['delay_ms'].to_i / 1000.0).clamp(0.1, 30.0).seconds)
            .perform_later(@conversation.id, @agent_inbox.id, @reply_to_message_id, chunks, 0, meta)
          Result.replied(nil)
        end

        # Fase B: RAG + portão de confiança + decisão de handoff. Já trata erro/timeout
        # do LLM como handoff seguro (reply pode vir nil).
        def answer
          ::Autonomia::Agents::Answerer.new(
            agent: @agent,
            query: query,
            history: history
          ).answer
        end

        # Handoff se a Fase B pediu OU não há texto de resposta para entregar.
        def handoff?(result)
          result.nil? || result.handoff[:should] || result.reply.blank?
        end

        def handoff(result, error: nil)
          ::Autonomia::Agents::Operate::HandoffHandler.new(
            conversation: @conversation,
            agent_inbox: @agent_inbox,
            result: result
          ).perform
          error ? Result.failed(error) : Result.handed_off
        end

        # Reavaliação de estado FRESCO dentro do lock: a conversa ainda está sob comando do
        # bot (pending + unassigned)? Se um humano assumiu durante a chamada à IA, NÃO posta.
        def still_eligible?
          @conversation.reload.pending? && @conversation.assignee_id.blank?
        end

        # Idempotência: já existe uma resposta outgoing do bot para ESTA mensagem incoming?
        # Bloqueia post duplicado num retry do Sidekiq que ocorra após um post bem-sucedido.
        def already_replied?
          return false if @reply_to_message_id.blank?

          # `content_attributes` é coluna `json` gravada via Rails `store(coder: JSON)`,
          # i.e. STRING JSON dentro de json: `->>` devolve NULL e nunca casa, e no `::text`
          # as aspas internas vêm ESCAPADAS (`\"autonomia_reply_to_message_id\":123`). O id
          # serializa como NÚMERO (Integer do arg do Sidekiq) — `...:123` sem aspas — mas o
          # regex tolera também a forma string (`"?...?"`). Fronteira `[,}]` evita casar 12 em
          # 123. Sem isto a guarda anti-duplicata ficaria sempre falsa (retry -> resposta dupla).
          id = Regexp.escape(@reply_to_message_id.to_s)
          pattern = %(autonomia_reply_to_message_id\\\\?":"?#{id}"?[,}])
          @conversation.messages.outgoing.where(sender_type: 'AgentBot')
                       .where('content_attributes::text ~ ?', pattern)
                       .exists?
        end

        # query = última mensagem INCOMING pública (o que o contato acaba de perguntar).
        def query
          recent_messages.reverse.find(&:incoming?)&.content.to_s
        end

        # history = N últimas mensagens públicas (≤ HISTORY_MAX_TURNS pares), em ordem
        # cronológica, mapeadas para o formato do Answerer: incoming -> user,
        # outgoing -> assistant. Activity/private já são excluídas pelo scope `chat`.
        def history
          recent_messages.map do |message|
            { role: message.incoming? ? 'user' : 'assistant', content: message.content.to_s }
          end
        end

        # Mensagens públicas, não-activity, mais recentes -> mais antigas no banco;
        # devolvidas em ordem cronológica (ascendente). Limite generoso (pares*2).
        def recent_messages
          @recent_messages ||= @conversation.messages
                                            .chat
                                            .reorder(created_at: :desc)
                                            .limit(::Autonomia::Agents::Config::HISTORY_MAX_TURNS * 2)
                                            .to_a
                                            .reverse
        end

        # Caminho CANÔNICO channel-agnóstico (= Crm::FollowUps::MessageSender): a entrega
        # por canal (WhatsApp/Instagram/email/webchat) é feita pelos jobs de canal do
        # Chatwoot disparados nos callbacks da Message outgoing. Nada por-canal aqui.
        def post_reply!(text)
          Messages::MessageBuilder.new(
            nil,
            @conversation,
            ActionController::Parameters.new(
              content: text,
              message_type: 'outgoing',
              sender_type: 'AgentBot',
              sender_id: @agent_inbox.agent_bot_id, # AgentBot nativo-espelho
              private: false,
              content_attributes: {
                autonomia_agent_id: @agent.id,
                autonomia_reply_to_message_id: @reply_to_message_id
              }
            )
          ).perform
        end
      end
    end
  end
end
