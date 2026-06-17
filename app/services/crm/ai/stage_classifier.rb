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
            }
          },
          required: %w[suggested_stage_id confidence reasoning value handoff],
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
        PROMPT
      end

      def handoff_instructions
        return 'Handoff desativado para este estágio: retorne "handoff": null.' unless @handoff_enabled

        agents = @eligible_agents.any? ? @eligible_agents.join(', ') : 'nenhum informado'
        <<~HANDOFF.strip
          Handoff para humano: avalie se a conversa atende o GATILHO abaixo. Se atender, retorne "handoff" com should_handoff=true e um motivo curto; senão should_handoff=false (ou "handoff": null).
          GATILHO DE HANDOFF: #{@handoff_trigger.presence || 'quando o cliente pedir explicitamente um atendente humano.'}
          Agentes disponíveis nesta caixa: #{agents}. Se o cliente citar/pedir um agente específico que esteja nessa lista, coloque o nome em "suggested_agent"; senão suggested_agent=null. Não invente nomes fora da lista.
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
          eligible_agents: @eligible_agents
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
