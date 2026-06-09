class Captain::Tools::FaqLookupTool < Captain::Tools::BasePublicTool
  description 'Search FAQ responses using semantic similarity to find relevant answers'
  param :query, type: 'string', desc: 'The question or topic to search for in the FAQ database'

  def perform(_tool_context, query:)
    log_tool_usage('searching', { query: query })

    result = Captain::DocumentationSearchService.new(
      scope: @assistant.responses.approved,
      account_id: @assistant.account_id
    ).search(query)
    Captain::DocumentationSearchService.record(result)

    if result.empty?
      log_tool_usage('no_results', { query: query })
    else
      log_tool_usage('found_results', { query: query, count: result.matches.size, status: result.status, reason: result.reason })
    end

    Captain::DocumentationSearchService.format_for_tool(result, no_results_message: "No relevant FAQs found for: #{query}")
  end
end
