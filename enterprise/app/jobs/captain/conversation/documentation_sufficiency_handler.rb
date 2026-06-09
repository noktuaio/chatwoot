module Captain::Conversation::DocumentationSufficiencyHandler
  HIGH_RISK_TERMS = %w[
    price pricing cost billing bill paid free plan subscription legal compliance policy limit limits maximum minimum
    available availability current currently roadmap beta early access supported support self-hosted cloud region version
    provider integration account status
  ].freeze

  private

  def reset_documentation_searches
    Current.captain_documentation_searches = []
  end

  def clear_documentation_searches
    Current.captain_documentation_searches = nil
  end

  def inspect_documentation_sufficiency(message_history)
    searches = documentation_searches_for_inspection(message_history)
    return unless should_inspect_documentation_sufficiency?(message_history, searches)

    apply_documentation_sufficiency_inspection(documentation_sufficiency_inspection(message_history, searches))
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    Rails.logger.warn(
      "[CAPTAIN][ResponseBuilderJob] Documentation sufficiency check failed for account=#{account.id} " \
      "conversation=#{@conversation.display_id}: #{e.class.name}: #{e.message}"
    )
  end

  def should_inspect_documentation_sufficiency?(message_history, searches)
    return false unless documentation_sufficiency_gate_enabled?
    return false unless response_has_user_facing_answer?
    return false if searches.empty?

    documentation_sufficiency_check_needed?(message_history, searches)
  end

  def response_has_user_facing_answer?
    @response.present? &&
      @response['response'].present? &&
      @response['response'] != 'conversation_handoff' &&
      !@response['handoff_tool_called']
  end

  def documentation_searches_for_inspection(message_history)
    searches = Current.captain_documentation_searches.to_a
    return searches if searches.present?
    return [] unless high_risk_conversation?(message_history)

    [synthetic_no_results_search(message_history)]
  end

  def synthetic_no_results_search(message_history)
    {
      query: last_user_message_content(message_history),
      queries: [last_user_message_content(message_history)],
      status: 'weak',
      reason: 'no_documentation_search',
      matches: []
    }
  end

  def documentation_sufficiency_inspection(message_history, searches)
    Captain::Llm::DocumentationSufficiencyService.new(
      assistant: @assistant,
      conversation: @conversation
    ).evaluate(
      message_history: message_history,
      assistant_response: @response['response'],
      documentation_searches: searches
    )
  end

  def documentation_sufficiency_gate_enabled?
    ActiveModel::Type::Boolean.new.cast(@assistant.config['documentation_sufficiency_gate_enabled'])
  end

  def documentation_sufficiency_check_needed?(message_history, searches)
    searches.any? { |search| search[:status] == 'weak' || search['status'] == 'weak' } || high_risk_conversation?(message_history)
  end

  def high_risk_conversation?(message_history)
    text = "#{message_history.last(3).map { |message| message[:content] || message['content'] }.join(' ')} #{@response&.dig('response')}".downcase
    HIGH_RISK_TERMS.any? { |term| text.include?(term) }
  end

  def last_user_message_content(message_history)
    user_message = message_history.reverse.find { |message| (message[:role] || message['role']).to_s == 'user' }
    user_message && (user_message[:content] || user_message['content']).to_s
  end

  def apply_documentation_sufficiency_inspection(inspection)
    return unless inspection['decision'] == 'insufficient'

    fallback_response = inspection['fallback_response'].presence || default_documentation_sufficiency_fallback
    @response.merge!(
      'response' => fallback_response,
      'action' => 'continue',
      'action_reason' => 'missing_docs_bounded_answer',
      'action_source' => 'documentation_sufficiency',
      'documentation_sufficiency_reason' => inspection['reason'],
      'documentation_sufficiency_model' => inspection['model']
    )
  end

  def default_documentation_sufficiency_fallback
    "I couldn't find enough information to answer that confidently. Would you like me to connect you with a support person?"
  end
end
