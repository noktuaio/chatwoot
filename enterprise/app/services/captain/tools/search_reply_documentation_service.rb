class Captain::Tools::SearchReplyDocumentationService < RubyLLM::Tool
  prepend Captain::Tools::Instrumentation

  description 'Search and retrieve documentation/FAQs from knowledge base'

  param :query, desc: 'Search Query', required: true

  def initialize(account:, assistant: nil)
    @account = account
    @assistant = assistant
    super()
  end

  def name
    'search_documentation'
  end

  def execute(query:)
    Rails.logger.info { "#{self.class.name}: #{query}" }

    translated_query = Captain::Llm::TranslateQueryService
                       .new(account: @account)
                       .translate(query, target_language: @account.locale_english_name)

    result = Captain::DocumentationSearchService.new(
      scope: search_scope,
      account_id: @account.id
    ).search(translated_query)
    Captain::DocumentationSearchService.record(result)

    Captain::DocumentationSearchService.format_for_tool(result, no_results_message: 'No FAQs found for the given query')
  end

  private

  def search_scope
    return @assistant.responses.approved if @assistant.present?

    @account.captain_assistant_responses.approved
  end
end
