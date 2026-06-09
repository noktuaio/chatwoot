class Captain::DocumentationSearchService
  # pgvector cosine distance: lower is closer. This only marks retrieval confidence;
  # final answer support is checked by Captain::Llm::DocumentationSufficiencyService.
  CLOSE_MATCH_DISTANCE = 0.45
  TOP_MATCHES_TO_FORMAT = 5

  def initialize(scope:, account_id: nil)
    @scope = scope
    @account_id = account_id
  end

  def search(query)
    matches = @scope.search_with_metadata(query, account_id: @account_id)
    {
      query: query,
      queries: [query],
      matches: matches,
      status: status_for(matches),
      reason: reason_for(matches)
    }
  end

  def self.serialize(result)
    result.merge(matches: result[:matches].map(&:to_h))
  end

  def self.format_for_tool(result, no_results_message:)
    return "#{no_results_message}\n\n#{weak_instruction}" if result[:matches].empty?

    sections = [quality_section(result)]
    sections.concat(result[:matches].first(TOP_MATCHES_TO_FORMAT).map { |match| format_match(match) })
    sections.join("\n")
  end

  def self.format_match(match)
    response = match.response
    formatted_response = "\nQuestion: #{response.question}\nAnswer: #{response.answer}\n"
    if response.documentable.present? && response.documentable.try(:external_link)
      formatted_response += "Source: #{response.documentable.external_link}\n"
    end
    formatted_response += 'Retrieval: semantic'
    formatted_response += ", semantic_distance=#{format('%.4f', match.semantic_distance)}" if match.semantic_distance.present?
    "#{formatted_response}\n"
  end

  def self.quality_section(result)
    lines = ["Search quality: #{result[:status]}", "Search reason: #{result[:reason]}"]
    lines << "Search queries: #{result[:queries].join(' | ')}" if result[:queries].to_a.size > 1
    lines << weak_instruction if result[:status] == 'weak'
    lines.join("\n")
  end

  def self.weak_instruction
    [
      'Instruction: The retrieved documentation is missing or weak. Do not use it to make factual claims.',
      "Say you couldn't find enough information to answer confidently, ask one clarifying question if useful, or ask whether",
      'the user wants to talk to a support person.'
    ].join(' ')
  end

  private

  def status_for(matches)
    return 'weak' if matches.empty?

    close_match?(matches.first) ? 'found' : 'weak'
  end

  def reason_for(matches)
    return 'no_results' if matches.empty?

    top_match = matches.first
    return 'semantic_match' if close_match?(top_match)

    'low_retrieval_confidence'
  end

  def close_match?(match)
    match.semantic_distance.present? && match.semantic_distance <= CLOSE_MATCH_DISTANCE
  end
end
