class Captain::DocumentationSearchService
  MAX_ACCEPTABLE_COSINE_DISTANCE = 0.45
  MIN_ACCEPTABLE_KEYWORD_COVERAGE = 0.4
  TOP_MATCHES_TO_FORMAT = 5
  SEARCH_ATTEMPT_LIMIT = 3

  Result = Struct.new(:query, :queries, :matches, :status, :reason, keyword_init: true) do
    def weak?
      status == 'weak'
    end

    def empty?
      matches.empty?
    end

    def to_h
      {
        query: query,
        queries: queries,
        status: status,
        reason: reason,
        matches: matches.map(&:to_h)
      }
    end
  end

  def initialize(scope:, account_id: nil)
    @scope = scope
    @account_id = account_id
  end

  def search(query)
    matches = []
    queries = []

    search_queries(query).each do |search_query|
      queries << search_query
      matches = merge_matches(matches, @scope.search_with_metadata(search_query, account_id: @account_id))
      break if matches.first && sufficient_match?(matches.first)
    end

    Result.new(query: query, queries: queries, matches: matches, status: status_for(matches), reason: reason_for(matches))
  end

  def self.record(result)
    Current.captain_documentation_searches ||= []
    Current.captain_documentation_searches << result.to_h
  end

  def self.format_for_tool(result, no_results_message:)
    return "#{no_results_message}\n\n#{weak_instruction(result)}" if result.empty?

    sections = [quality_section(result)]
    sections.concat(result.matches.first(TOP_MATCHES_TO_FORMAT).map { |match| format_match(match) })
    sections.join("\n")
  end

  def self.format_match(match)
    response = match.response
    formatted_response = "\nQuestion: #{response.question}\nAnswer: #{response.answer}\n"
    if response.documentable.present? && response.documentable.try(:external_link)
      formatted_response += "Source: #{response.documentable.external_link}\n"
    end
    formatted_response += "Retrieval: #{match.retrieval_methods.join(', ')}"
    formatted_response += ", semantic_distance=#{format('%.4f', match.semantic_distance)}" if match.semantic_distance.present?
    formatted_response += ", keyword_coverage=#{format('%.2f', match.keyword_coverage)}" if match.keyword_score.positive?
    "#{formatted_response}\n"
  end

  def self.quality_section(result)
    lines = ["Search quality: #{result.status}", "Search reason: #{result.reason}"]
    lines << "Search queries: #{result.queries.join(' | ')}" if result.queries.to_a.size > 1
    lines << weak_instruction(result) if result.weak?
    lines.join("\n")
  end

  def self.weak_instruction(_result)
    [
      'Instruction: The retrieved documentation is missing or weak. Do not use it to make factual claims.',
      "Say you couldn't find enough information to answer confidently, ask one clarifying question if useful, or ask whether",
      'the user wants to talk to a support person.'
    ].join(' ')
  end

  private

  def search_queries(query)
    query = query.to_s.strip
    terms = Captain::AssistantResponse.search_terms(query)
    keyword_query = terms.join(' ')
    trailing_query = terms.last(8).join(' ')

    [query, keyword_query, trailing_query].filter_map(&:presence).uniq.first(SEARCH_ATTEMPT_LIMIT)
  end

  def merge_matches(existing_matches, new_matches)
    matches_by_response_id = existing_matches.index_by { |match| match.response.id }

    new_matches.each do |new_match|
      existing_match = matches_by_response_id[new_match.response.id]
      if existing_match
        merge_match!(existing_match, new_match)
      else
        matches_by_response_id[new_match.response.id] = new_match
      end
    end

    matches_by_response_id.values.sort_by do |match|
      [match.semantic_distance || 1.0, -match.keyword_score, match.response.id]
    end
  end

  def merge_match!(existing_match, new_match)
    existing_match.semantic_distance = best_semantic_distance(existing_match.semantic_distance, new_match.semantic_distance)
    existing_match.keyword_score = [existing_match.keyword_score, new_match.keyword_score].max
    existing_match.keyword_coverage = [existing_match.keyword_coverage, new_match.keyword_coverage].max
    existing_match.matched_terms |= new_match.matched_terms
    existing_match.retrieval_methods |= new_match.retrieval_methods
  end

  def best_semantic_distance(existing_distance, new_distance)
    return new_distance if existing_distance.blank?
    return existing_distance if new_distance.blank?

    [existing_distance, new_distance].min
  end

  def status_for(matches)
    return 'weak' if matches.empty?

    sufficient_match?(matches.first) ? 'sufficient' : 'weak'
  end

  def reason_for(matches)
    return 'no_results' if matches.empty?

    top_match = matches.first
    return 'semantic_match' if top_match.semantic_distance.present? && top_match.semantic_distance <= MAX_ACCEPTABLE_COSINE_DISTANCE
    return 'keyword_match' if top_match.keyword_coverage >= MIN_ACCEPTABLE_KEYWORD_COVERAGE

    'low_retrieval_confidence'
  end

  def sufficient_match?(match)
    semantic_match?(match) || keyword_match?(match)
  end

  def semantic_match?(match)
    match.semantic_distance.present? && match.semantic_distance <= MAX_ACCEPTABLE_COSINE_DISTANCE
  end

  def keyword_match?(match)
    match.keyword_coverage >= MIN_ACCEPTABLE_KEYWORD_COVERAGE
  end
end
