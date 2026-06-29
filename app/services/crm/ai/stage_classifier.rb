module Crm
  module Ai
    class StageClassifier
      CLASSIFICATION_SCHEMA = {
        name: 'stage_classification',
        schema: {
          type: 'object',
          properties: {
            suggested_stage_id: { type: 'integer' },
            confidence: { type: 'number', minimum: 0, maximum: 1 },
            reasoning: { type: 'string', maxLength: 500 },
            value: {
              type: %w[object null],
              description: 'Valor do negócio citado na conversa. null se nenhum valor for mencionado.',
              properties: {
                amount_cents: { type: 'integer', minimum: 0, description: 'Valor em centavos (ex.: R$ 1.500,00 => 150000).' },
                currency: { type: 'string', description: 'Código ISO da moeda (ex.: BRL, USD).' }
              },
              required: %w[amount_cents currency],
              additionalProperties: false
            },
            handoff: {
              type: %w[object null],
              description: 'Preencha quando a conversa atender o gatilho de handoff informado. null caso contrário.',
              properties: {
                should_handoff: { type: 'boolean', description: 'true se a conversa deve ser passada para um atendente humano agora.' },
                reason: { type: 'string', maxLength: 300, description: 'Motivo curto do handoff.' },
                suggested_agent: { type: %w[string null], description: 'Nome do agente citado/pedido na conversa, se houver; senão null.' }
              },
              required: %w[should_handoff reason suggested_agent],
              additionalProperties: false
            },
            callback_request: {
              type: %w[object null],
              description: 'Preencha SOMENTE quando o cliente pedir um retorno/contato numa DATA ou HORA concreta. null caso contrário.',
              properties: {
                detected: { type: 'boolean', description: 'true se há pedido de retorno com data/hora concreta.' },
                requested_at: { type: %w[string null], description: 'Data/hora LOCAL resolvida no formato "YYYY-MM-DDTHH:MM" (sem fuso). null se não der para resolver uma data concreta.' },
                requested_at_text: { type: %w[string null], description: 'Trecho original do pedido (ex.: "me liga terça que vem de tarde").' },
                confidence: { type: 'number', minimum: 0, maximum: 1, description: 'Confiança de que há um pedido de retorno com data concreta.' }
              },
              required: %w[detected requested_at requested_at_text confidence],
              additionalProperties: false
            }
          },
          required: %w[suggested_stage_id confidence reasoning value handoff callback_request],
          additionalProperties: false
        }
      }.freeze

      def initialize(card:, client:, stages:, context:, model: Config::MODEL_CLASSIFY, reasoning_effort: 'low',
                     handoff_enabled: false, handoff_trigger: '', eligible_agents: [])
        @card = card
        @client = client
        @stages = stages
        @context = context
        @model = model
        @reasoning_effort = reasoning_effort
        @handoff_enabled = handoff_enabled
        @handoff_trigger = handoff_trigger.to_s.strip
        @eligible_agents = Array(eligible_agents)
      end

      def perform
        response = @client.create(
          model: @model,
          instructions: instructions,
          input: user_input,
          schema: CLASSIFICATION_SCHEMA,
          reasoning_effort: @reasoning_effort
        )

        JSON.parse(response[:text]).with_indifferent_access.merge(
          model_used: @model,
          usage: response[:usage],
          response_id: response[:response_id]
        )
      end

      private

      def instructions
        <<~PROMPT.strip
          Você classifica cards de CRM Kanban em estágios de funil comercial no Brasil.
          Responda apenas com JSON válido no schema solicitado.
          Use os critérios de cada estágio abaixo. Se nenhum estágio se encaixar com confiança, escolha o estágio atual.
          Confiança 0.0 a 1.0. Seja conservador em mover para "Perdido".
          Se a conversa mencionar explicitamente um valor de negócio/proposta/contrato, preencha "value" (amount_cents em centavos e currency ISO). Se nenhum valor for citado, retorne "value": null. Não invente valores.
          #{handoff_instructions}
          #{callback_instructions}
        PROMPT
      end

      # Detecção de pedido de RETORNO com data ("me liga terça", "retorna dia 15 às 10h").
      # Estático (prefix-stable p/ prompt caching): os valores temporais (now_local, weekday,
      # timezone, default_hour) NÃO são interpolados aqui — vão nos dados de entrada (user_input),
      # senão o relógio mudaria o prefixo a cada chamada e o cache nunca reusaria.
      def callback_instructions
        <<~CB.strip
          RETORNO COM DATA: avalie se o cliente pediu para ser contatado/retornado numa DATA ou HORA concreta.
          A data/hora ATUAL (now_local), o dia da semana (weekday), o fuso (timezone) e a hora padrão (default_hour)
          estão nos DADOS DE ENTRADA. Resolva expressões relativas a partir de now_local:
          "amanhã", "semana que vem", "depois do feriado", "dia 15", "terça às 10h" → uma data LOCAL futura concreta.
          Regras de hora: "de manhã"→09:00, "de tarde"→14:00, "de noite"→19:00; sem hora/período → use default_hour.
          Preencha "callback_request" com detected=true, requested_at no formato "YYYY-MM-DDTHH:MM" (hora LOCAL, sem fuso),
          requested_at_text (trecho original) e confidence. Se o pedido for VAGO ("me liga depois", "qualquer hora", sem
          data resolvível) ou NÃO houver pedido de retorno, retorne "callback_request": null. NUNCA invente uma data.
        CB
      end

      # Estático (prefix-stable p/ prompt caching): status/gatilho/agentes de handoff NÃO são
      # interpolados — vão nos dados de entrada (handoff_enabled, handoff_trigger, eligible_agents),
      # senão variariam o prefixo por caixa/estágio.
      def handoff_instructions
        <<~HANDOFF.strip
          HANDOFF PARA HUMANO: o status (handoff_enabled), o GATILHO (handoff_trigger) e os agentes disponíveis
          (eligible_agents) estão nos DADOS DE ENTRADA.
          Se handoff_enabled for false, retorne "handoff": null.
          Se handoff_enabled for true, avalie se a conversa atende o handoff_trigger (quando vazio, use "o cliente pediu
          explicitamente um atendente humano"): se atender, retorne "handoff" com should_handoff=true e um motivo curto;
          senão should_handoff=false (ou "handoff": null).
          Se o cliente citar/pedir um agente presente em eligible_agents, coloque o nome em "suggested_agent"; senão
          suggested_agent=null. Não invente nomes fora da lista.
        HANDOFF
      end

      def user_input
        {
          card: {
            id: @card.id,
            title: @card.title,
            current_stage_id: @context[:current_stage][:id],
            current_stage_name: @context[:current_stage][:name]
          },
          stages: @stages.map { |stage| stage_payload(stage) },
          conversation_summary: @context[:summary],
          recent_messages: @context[:recent_messages],
          handoff_enabled: @handoff_enabled,
          handoff_trigger: @handoff_trigger,
          eligible_agents: @eligible_agents,
          now_local: @context.dig(:temporal, :now_local),
          weekday: @context.dig(:temporal, :weekday),
          timezone: @context.dig(:temporal, :timezone),
          default_hour: @context.dig(:temporal, :default_hour) || 9
        }.to_json
      end

      def stage_payload(stage)
        {
          id: stage.id,
          name: stage.name,
          criteria: Config.stage_ai_criteria(stage)
        }
      end
    end
  end
end
