class Captain::Tools::SearchDocumentationService < Captain::Tools::BaseTool
  def initialize(assistant, user: nil, on_search: nil)
    super(assistant, user: user)
    @on_search = on_search
  end

  def self.name
    'search_documentation'
  end
  description 'Search and retrieve documentation from knowledge base'

  param :query, desc: 'Search Query', required: true

  def execute(query:)
    Rails.logger.info { "#{self.class.name}: #{query}" }

    translated_query = Captain::Llm::TranslateQueryService
                       .new(account: assistant.account)
                       .translate(query, target_language: assistant.account.locale_english_name)

    result = Captain::DocumentationSearchService.new(
      scope: assistant.responses.approved,
      account_id: assistant.account_id
    ).search(translated_query)
    @on_search&.call(Captain::DocumentationSearchService.serialize(result))

    Captain::DocumentationSearchService.format_for_tool(result, no_results_message: 'No FAQs found for the given query')
  end
end
