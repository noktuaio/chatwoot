class Captain::Llm::DocumentationSufficiencyService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  MAX_CONTEXT_MESSAGES = 6
  MAX_SEARCHES = 3
  MAX_MATCHES_PER_SEARCH = 5
  MAX_ANSWER_CHARS = 700

  def initialize(assistant:, conversation:)
    super()
    @assistant = assistant
    @conversation = conversation
    @temperature = 0.0
  end

  def evaluate(message_history:, assistant_response:, documentation_searches:)
    user_prompt = inspection_user_prompt(
      message_history: message_history,
      assistant_response: assistant_response,
      documentation_searches: documentation_searches
    )

    response = instrument_llm_call(instrumentation_params(user_prompt, documentation_searches)) do
      chat(model: @model, temperature: @temperature)
        .with_schema(Captain::DocumentationSufficiencySchema)
        .with_instructions(system_prompt)
        .ask(user_prompt)
    end

    parsed = parse_response(response.content)
    normalize_response(parsed, response.content)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    Rails.logger.warn(
      "[CAPTAIN][DocumentationSufficiency] Failed for conversation #{@conversation.display_id}: #{e.class.name}: #{e.message}"
    )
    { 'decision' => nil, 'reason' => nil, 'error' => e.message, 'model' => @model }
  end

  private

  def system_prompt
    <<~PROMPT
      You are checking whether a customer-facing assistant response is supported by retrieved documentation.

      Use only the conversation context, assistant response, and retrieved documentation search results provided.
      Do not use outside knowledge.

      Return "insufficient" when the assistant makes factual claims that are not supported by the retrieved documentation.
      Treat prior assistant messages as claims, not evidence. They do not support the new answer by themselves.
      Conversation context can support the answer only when the user explicitly provided the relevant fact, constraint, or artifact.
      Check generic sufficiency dimensions:
      - same entity, product, platform, integration, or account object
      - same user intent, not just a nearby topic
      - requested constraints such as plan, edition, region, channel, version, provider, billing period, availability, or current status
      - high-risk claims such as pricing, billing, legal/compliance, limits, availability, platform support, roadmap, or account status
      - evidence specificity; generic broad docs are not enough for specific claims

      Return "sufficient" when the documentation directly supports the response, or when the response only asks a clarifying
      question, gives a safe bounded no-answer, offers handoff, or restates user-provided context without adding external claims.
      If documentation is missing or weak and the response gives factual claims, advice, instructions, examples, links, prices,
      limits, availability, troubleshooting steps, product behavior, platform behavior, or account-specific statements, return "insufficient".

      If decision is "insufficient", write fallback_response in the user's language. It should be brief, say you could not find
      enough information to answer confidently, and ask whether the user wants to talk to a support person when appropriate.
      If decision is not "insufficient", fallback_response must be empty.
    PROMPT
  end

  def inspection_user_prompt(message_history:, assistant_response:, documentation_searches:)
    <<~PROMPT
      <conversation_context>
      #{format_conversation_context(message_history)}
      </conversation_context>

      <retrieved_documentation>
      #{format_documentation_searches(documentation_searches)}
      </retrieved_documentation>

      <assistant_response>
      #{assistant_response}
      </assistant_response>
    PROMPT
  end

  def format_documentation_searches(searches)
    searches.to_a.last(MAX_SEARCHES).map.with_index(1) do |search, index|
      matches = search[:matches] || search['matches'] || []
      <<~SEARCH
        Search #{index}
        query: #{search[:query] || search['query']}
        status: #{search[:status] || search['status']}
        reason: #{search[:reason] || search['reason']}
        matches:
        #{format_documentation_matches(matches)}
      SEARCH
    end.join("\n")
  end

  def format_documentation_matches(matches)
    matches.to_a.first(MAX_MATCHES_PER_SEARCH).map.with_index(1) do |match, index|
      <<~MATCH
        #{index}. question: #{match_value(match, :question)}
           answer: #{truncate_text(match_value(match, :answer))}
           source: #{match_value(match, :source)}
           semantic_distance: #{match_value(match, :semantic_distance)}
           keyword_coverage: #{match_value(match, :keyword_coverage)}
           retrieval_methods: #{Array(match_value(match, :retrieval_methods)).join(', ')}
      MATCH
    end.join("\n")
  end

  def match_value(match, key) = match[key] || match[key.to_s]

  def normalize_messages(message_history)
    message_history.filter_map do |message|
      role = message[:role] || message['role']
      next if role.blank?

      { role: role.to_s, content: normalize_content(message[:content] || message['content']) }
    end
  end

  def normalize_content(content)
    return content if content.is_a?(String)
    return content.filter_map { |part| part[:text] || part['text'] if text_part?(part) }.join("\n") if content.is_a?(Array)

    content.to_s
  end

  def text_part?(part)
    return false unless part.is_a?(Hash)

    (part[:type] || part['type']).to_s == 'text'
  end

  def format_conversation_context(messages)
    normalize_messages(messages).last(MAX_CONTEXT_MESSAGES).filter_map do |message|
      content = message[:content].to_s.strip
      next if content.blank?

      "#{role_label(message[:role])}: #{content}"
    end.join("\n")
  end

  def role_label(role) = { 'user' => 'User', 'assistant' => 'Assistant' }.fetch(role, role.to_s.titleize)

  def parse_response(content)
    return content if content.is_a?(Hash)

    JSON.parse(sanitize_json_response(content))
  rescue JSON::ParserError, TypeError
    {}
  end

  def normalize_response(parsed, raw_content)
    decision = parsed['decision'].to_s
    reason = parsed['reason'].to_s
    return invalid_response(raw_content) unless Captain::DocumentationSufficiencySchema::DECISIONS.include?(decision)

    {
      'decision' => decision,
      'reason' => reason.presence,
      'fallback_response' => parsed['fallback_response'].to_s,
      'raw_response' => raw_content,
      'model' => @model
    }
  end

  def invalid_response(raw_content)
    {
      'decision' => nil,
      'reason' => nil,
      'fallback_response' => nil,
      'raw_response' => raw_content,
      'error' => 'invalid_documentation_sufficiency_response',
      'model' => @model
    }
  end

  def instrumentation_params(user_prompt, documentation_searches)
    {
      span_name: 'llm.captain.documentation_sufficiency',
      model: @model,
      temperature: @temperature,
      account_id: @conversation.account_id,
      conversation_id: @conversation.display_id,
      feature_name: 'documentation_sufficiency',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: user_prompt }
      ],
      metadata: {
        assistant_id: @assistant.id,
        channel_type: @conversation.inbox&.channel_type,
        source: 'response_builder'
      }.merge(search_metadata(documentation_searches))
    }
  end

  def search_metadata(documentation_searches)
    searches = documentation_searches.to_a
    {
      search_count: searches.length,
      search_statuses: searches.filter_map { |search| search[:status] || search['status'] }.join(','),
      search_reasons: searches.filter_map { |search| search[:reason] || search['reason'] }.join(',')
    }
  end

  def truncate_text(text)
    text = text.to_s
    return text if text.length <= MAX_ANSWER_CHARS

    "#{text.first(MAX_ANSWER_CHARS)}..."
  end
end
