module Captain::Conversation::DocumentationSupportGate
  private

  def check_documentation_support(message_history)
    return unless documentation_gate_enabled?
    return unless customer_reply?

    review = review_documentation_support(message_history, documentation_evidence(message_history))
    apply_documentation_fallback(review)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    Rails.logger.warn(
      "[CAPTAIN][ResponseBuilderJob] Documentation support check failed for account=#{account.id} " \
      "conversation=#{@conversation.display_id}: #{e.class.name}: #{e.message}"
    )
  end

  def documentation_gate_enabled?
    ActiveModel::Type::Boolean.new.cast(@assistant.config['documentation_sufficiency_gate_enabled'])
  end

  def customer_reply?
    @response.present? &&
      @response['response'].present? &&
      @response['response'] != 'conversation_handoff' &&
      !@response['handoff_tool_called']
  end

  def documentation_evidence(message_history)
    searches = @response['documentation_searches'].to_a
    return searches if searches.present?

    [no_documentation_search(last_user_message(message_history))]
  end

  def no_documentation_search(query)
    {
      query: query,
      queries: [query],
      status: 'weak',
      reason: 'no_documentation_search',
      matches: []
    }
  end

  def review_documentation_support(message_history, evidence)
    Captain::Llm::DocumentationSufficiencyService.new(
      assistant: @assistant,
      conversation: @conversation
    ).evaluate(
      message_history: message_history,
      assistant_response: @response['response'],
      documentation_searches: evidence
    )
  end

  def last_user_message(message_history)
    message = message_history.reverse.find { |item| (item[:role] || item['role']).to_s == 'user' }
    message && (message[:content] || message['content']).to_s
  end

  def apply_documentation_fallback(review)
    return unless review['decision'] == 'insufficient'

    @response.merge!(
      'response' => review['fallback_response'].presence || default_documentation_fallback,
      'action' => 'continue',
      'action_reason' => 'missing_docs_bounded_answer',
      'action_source' => 'documentation_support',
      'documentation_sufficiency_reason' => review['reason'],
      'documentation_sufficiency_model' => review['model']
    )
  end

  def default_documentation_fallback
    "I couldn't find enough information to answer that confidently. Would you like me to connect you with a support person?"
  end
end
