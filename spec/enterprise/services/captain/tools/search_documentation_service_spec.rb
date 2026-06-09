require 'rails_helper'

RSpec.describe Captain::Tools::SearchDocumentationService do
  let(:assistant) { create(:captain_assistant) }
  let(:service) { described_class.new(assistant) }
  let(:question) { 'How to create a new account?' }
  let(:answer) { 'You can create a new account by clicking on the Sign Up button.' }
  let(:external_link) { 'https://example.com/docs/create-account' }

  describe '#name' do
    it 'returns the correct service name' do
      expect(service.name).to eq('search_documentation')
    end
  end

  describe '#description' do
    it 'returns the service description' do
      expect(service.description).to eq('Search and retrieve documentation from knowledge base')
    end
  end

  describe '#parameters' do
    it 'defines query parameter' do
      expect(service.parameters.keys).to contain_exactly(:query)
    end
  end

  describe '#execute' do
    let(:documentation_search_service) { instance_double(Captain::DocumentationSearchService) }
    let(:translate_query_service) { instance_double(Captain::Llm::TranslateQueryService) }
    let!(:response) do
      create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: question,
        answer: answer,
        status: 'approved'
      )
    end

    let(:documentable) { create(:captain_document, external_link: external_link) }
    let(:match) do
      Captain::AssistantResponse::SearchMatch.new(
        response: response,
        semantic_distance: 0.2,
        keyword_score: 0,
        keyword_coverage: 0.0,
        matched_terms: [],
        retrieval_methods: ['semantic']
      )
    end

    before do
      allow(Captain::Llm::TranslateQueryService).to receive(:new).and_return(translate_query_service)
      allow(translate_query_service).to receive(:translate).and_return(question)
      allow(Captain::DocumentationSearchService).to receive(:new)
        .with(scope: anything, account_id: assistant.account_id)
        .and_return(documentation_search_service)
    end

    context 'when matching responses exist' do
      it 'returns formatted responses for the search query' do
        response.update(documentable: documentable)
        search_result = Captain::DocumentationSearchService::Result.new(
          query: question,
          queries: [question],
          matches: [match],
          status: 'sufficient',
          reason: 'semantic_match'
        )
        allow(documentation_search_service).to receive(:search).with(question).and_return(search_result)

        result = service.execute(query: question)

        expect(result).to include(question)
        expect(result).to include(answer)
        expect(result).to include(external_link)
      end
    end

    context 'when no matching responses exist' do
      it 'returns a bounded no-results instruction' do
        search_result = Captain::DocumentationSearchService::Result.new(
          query: question,
          queries: [question],
          matches: [],
          status: 'weak',
          reason: 'no_results'
        )
        allow(documentation_search_service).to receive(:search).with(question).and_return(search_result)

        result = service.execute(query: question)

        expect(result).to include('No FAQs found for the given query')
        expect(result).to include('Do not use it to make factual claims')
      end
    end
  end
end
