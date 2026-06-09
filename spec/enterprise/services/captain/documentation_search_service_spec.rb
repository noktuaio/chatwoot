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

  def search_match(semantic_distance:, response_record: response)
    Captain::AssistantResponse::SearchMatch.new(
      response: response_record,
      semantic_distance: semantic_distance
    )
  end

  def search_result(matches:, status:, reason:, query: 'billing')
    {
      query: query,
      queries: [query],
      matches: matches,
      status: status,
      reason: reason
    }
  end

  describe '#search' do
    it 'marks weak semantic matches as weak' do
      query = 'How do I check limits for my current monthly plan?'
      weak_match = search_match(semantic_distance: 0.9)

      allow(scope).to receive(:search_with_metadata).with(query, account_id: 1).and_return([weak_match])

      result = service.search(query)

      expect(result[:status]).to eq('weak')
      expect(result[:reason]).to eq('low_retrieval_confidence')
      expect(result[:queries]).to eq([query])
    end

    it 'marks close semantic matches as found' do
      query = 'Where do I find billing settings?'
      close_match = search_match(semantic_distance: 0.2)

      allow(scope).to receive(:search_with_metadata).with(query, account_id: 1).and_return([close_match])

      result = service.search(query)

      expect(result[:status]).to eq('found')
      expect(result[:reason]).to eq('semantic_match')
      expect(result[:queries]).to eq([query])
    end
  end

  describe '.format_for_tool' do
    it 'adds a bounded-answer instruction when no documentation is found' do
      result = search_result(query: 'unknown topic', matches: [], status: 'weak', reason: 'no_results')

      formatted_result = described_class.format_for_tool(result, no_results_message: 'No FAQs found')

      expect(formatted_result).to include('No FAQs found')
      expect(formatted_result).to include('Do not use it to make factual claims')
    end
  end

  describe '.serialize' do
    it 'formats search metadata for the response-level support gate' do
      result = search_result(matches: [search_match(semantic_distance: 0.2)], status: 'found', reason: 'semantic_match')

      serialized_result = described_class.serialize(result)

      expect(serialized_result[:status]).to eq('found')
      expect(serialized_result[:matches].first[:semantic_distance]).to eq(0.2)
    end
  end
end
