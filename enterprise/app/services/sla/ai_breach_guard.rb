class Sla::AiBreachGuard
  CONFIDENCE_THRESHOLD = 0.6 # LOCKED decision 3: fixed internal constant
  TRANSCRIPT_LIMIT = 20
  CONTENT_LIMIT = 500

  # OPENAI STRICT SCHEMA: every property listed in required, additionalProperties false.
  SCHEMA = {
    name: 'sla_breach_guard',
    schema: {
      type: 'object',
      properties: {
        customer_waiting: { type: 'boolean', description: 'true se há um cliente realmente esperando uma resposta NOSSA agora.' },
        reason: { type: 'string', maxLength: 300, description: 'Justificativa curta baseada APENAS na transcrição. Não invente fatos.' },
        confidence: { type: 'number', minimum: 0, maximum: 1 }
      },
      required: %w[customer_waiting reason confidence],
      additionalProperties: false
    }
  }.freeze

  INSTRUCTIONS = <<~PROMPT.freeze
    Você audita SLAs de atendimento no Brasil. Leia a transcrição (cliente x agente) e decida:
    há um cliente realmente esperando uma resposta NOSSA agora?
    Responda customer_waiting=false quando a pausa é saudável (relacionamento contínuo sem pendência),
    quando a bola está com o cliente (última pendência é dele), ou quando a conversa foi encerrada/resolvida.
    Responda customer_waiting=true quando existe pergunta, pedido ou pendência do cliente sem resposta nossa.
    Baseie-se SOMENTE na transcrição; não invente fatos. Em caso de dúvida, customer_waiting=true com confidence baixa.
    Responda apenas com JSON válido no schema solicitado.
  PROMPT

  def initialize(applied_sla:, breach_type:)
    @applied_sla = applied_sla
    @breach_type = breach_type.to_s
  end

  # true => suppress the breach (no SlaEvent). Fail-open: any error counts the breach.
  def skip_breach?
    return false unless @applied_sla.sla_policy.ai_skip_natural_pause?
    return false unless Crm::Ai::Config.enabled?
    return false unless @applied_sla.account.feature_enabled?('sla')

    credential = Crm::Ai::CredentialResolver.new(account: @applied_sla.account).resolve
    return false if credential.blank?
    return false if last_message_id.blank?

    decision = cached_decision || fresh_decision(credential)
    return false if decision.blank?

    decision['customer_waiting'] == false && decision['confidence'].to_f >= CONFIDENCE_THRESHOLD
  rescue StandardError => e
    Rails.logger.warn "SLA:: AiBreachGuard failed for applied_sla #{@applied_sla.id}: #{e.message}"
    false
  end

  private

  def conversation
    @applied_sla.conversation
  end

  # Reuse the cached decision while no new relevant message arrived (cost guard).
  def cached_decision
    cached = (@applied_sla.metadata || {})['ai_pause']
    return unless cached.is_a?(Hash)

    cached if cached['source_message_id'].present? && cached['source_message_id'] == last_message_id
  end

  def fresh_decision(credential)
    response = Crm::Ai::ResponsesClient.new(credential: credential).create(
      model: Crm::Ai::Config::MODEL_CLASSIFY,
      instructions: INSTRUCTIONS,
      input: transcript,
      schema: SCHEMA,
      reasoning_effort: 'low'
    )
    decision = JSON.parse(response[:text])
    # Cache only well-formed decisions; a malformed one would stick to the
    # current message id and silently pin the outcome until a new message.
    return unless decision.is_a?(Hash) && [true, false].include?(decision['customer_waiting']) && decision['confidence'].is_a?(Numeric)

    persist_cache(decision)
    decision
  end

  def persist_cache(decision)
    @applied_sla.update!(
      metadata: (@applied_sla.metadata || {}).merge(
        'ai_pause' => {
          'customer_waiting' => decision['customer_waiting'],
          'reason' => decision['reason'],
          'confidence' => decision['confidence'],
          'source_message_id' => last_message_id,
          'breach_type' => @breach_type,
          'decided_at' => Time.zone.now.iso8601
        }
      )
    )
  end

  # Message has a default_scope ordered ASC — always .reorder for recent messages.
  def last_message_id
    @last_message_id ||= relevant_messages.reorder(created_at: :desc).first&.id
  end

  def relevant_messages
    conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
  end

  def transcript
    lines = relevant_messages.reorder(created_at: :desc).limit(TRANSCRIPT_LIMIT).to_a.reverse.map do |message|
      role = message.incoming? ? 'cliente' : 'agente'
      "[#{role}] #{message.content.to_s.truncate(CONTENT_LIMIT)}"
    end
    "Tipo de prazo em quebra: #{@breach_type.upcase}\nTranscrição (mais antiga -> mais recente):\n#{lines.join("\n")}"
  end
end
