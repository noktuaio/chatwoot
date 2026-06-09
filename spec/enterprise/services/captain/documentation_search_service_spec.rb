require 'rails_helper'

RSpec.describe Captain::DocumentationSearchService do
  let(:scope_class) do
    Class.new do
      def search_with_metadata(*)
        []
      end
    end
  end
  let(:scope) { scope_class.new }
  let(:service) { described_class.new(scope: scope, account_id: 1) }
  let(:response) do
    instance_double(
      Captain::AssistantResponse,
      id: 1,
      question: 'How do plan limits work?',
      answer: 'Monthly limits are shown in billing settings.',
      documentable: nil
    )
  end

  def search_match(semantic_distance:, keyword_coverage:, keyword_score: 0, response_record: response)
    Captain::AssistantResponse::SearchMatch.new(
      response: response_record,
      semantic_distance: semantic_distance,
      keyword_score: keyword_score,
      keyword_coverage: keyword_coverage,
      matched_terms: [],
      retrieval_methods: ['semantic']
    )
  end

  describe '#search' do
    it 'retries with generic query variants when the original query has weak matches' do
      query = 'How do I check limits for my current monthly plan?'
      weak_match = search_match(semantic_distance: 0.9, keyword_coverage: 0.0)
      sufficient_match = search_match(semantic_distance: 0.8, keyword_coverage: 0.4, keyword_score: 2)

      allow(scope).to receive(:search_with_metadata).with(query, account_id: 1).and_return([weak_match])
      allow(scope).to receive(:search_with_metadata)
        .with('check limits current monthly plan', account_id: 1)
        .and_return([sufficient_match])

      result = service.search(query)

      expect(result.status).to eq('sufficient')
      expect(result.reason).to eq('keyword_match')
      expect(result.queries).to eq([query, 'check limits current monthly plan'])
      expect(result.matches.first.keyword_coverage).to eq(0.4)
    end

    it 'stops after the first query when retrieval confidence is sufficient' do
      query = 'Where do I find billing settings?'
      sufficient_match = search_match(semantic_distance: 0.2, keyword_coverage: 0.0)

      allow(scope).to receive(:search_with_metadata).with(query, account_id: 1).and_return([sufficient_match])

      result = service.search(query)

      expect(result.status).to eq('sufficient')
      expect(result.reason).to eq('semantic_match')
      expect(result.queries).to eq([query])
    end
  end

  describe '.format_for_tool' do
    it 'adds a bounded-answer instruction when no documentation is found' do
      result = described_class::Result.new(
        query: 'unknown topic',
        queries: ['unknown topic'],
        matches: [],
        status: 'weak',
        reason: 'no_results'
      )

      formatted_result = described_class.format_for_tool(result, no_results_message: 'No FAQs found')

      expect(formatted_result).to include('No FAQs found')
      expect(formatted_result).to include('Do not use it to make factual claims')
    end
  end

  describe '.record' do
    it 'stores search metadata on Current for the response-level sufficiency gate' do
      result = described_class::Result.new(
        query: 'billing',
        queries: ['billing'],
        matches: [search_match(semantic_distance: 0.2, keyword_coverage: 0.0)],
        status: 'sufficient',
        reason: 'semantic_match'
      )

      described_class.record(result)

      expect(Current.captain_documentation_searches.first[:status]).to eq('sufficient')
      expect(Current.captain_documentation_searches.first[:matches].first[:semantic_distance]).to eq(0.2)
    ensure
      Current.captain_documentation_searches = nil
    end
  end
end
