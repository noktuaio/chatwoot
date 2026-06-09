require 'rails_helper'

RSpec.describe Captain::Tools::FaqLookupTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:documentation_searches) { [] }
  let(:tool_context) { Struct.new(:state).new({ documentation_searches: documentation_searches }) }
  let(:documentation_search_service) { instance_double(Captain::DocumentationSearchService) }

  before do
    allow(Captain::DocumentationSearchService).to receive(:new)
      .with(scope: anything, account_id: assistant.account_id)
      .and_return(documentation_search_service)
  end

  describe '#description' do
    it 'returns the correct description' do
      expect(tool.description).to eq('Search FAQ responses using semantic similarity to find relevant answers')
    end
  end

  describe '#parameters' do
    it 'returns the correct parameters' do
      expect(tool.parameters).to have_key(:query)
      expect(tool.parameters[:query].name).to eq(:query)
      expect(tool.parameters[:query].type).to eq('string')
      expect(tool.parameters[:query].description).to eq('The question or topic to search for in the FAQ database')
    end
  end

  describe '#perform' do
    def search_match(response)
      Captain::AssistantResponse::SearchMatch.new(response: response, semantic_distance: 0.2)
    end

    def search_result(query:, matches:, status:, reason:)
      {
        query: query,
        queries: [query],
        matches: matches,
        status: status,
        reason: reason
      }
    end

    context 'when FAQs exist' do
      let(:document) { create(:captain_document, assistant: assistant) }
      let!(:response1) do
        create(:captain_assistant_response,
               assistant: assistant,
               account: account,
               question: 'How to reset password?',
               answer: 'Click on forgot password link',
               documentable: document,
               status: 'approved')
      end
      let!(:response2) do
        create(:captain_assistant_response,
               assistant: assistant,
               account: account,
               question: 'How to change email?',
               answer: 'Go to settings and update email',
               status: 'approved')
      end

      before do
        matches = [response1, response2].map { |response| search_match(response) }
        allow(documentation_search_service).to receive(:search).and_return(
          search_result(query: 'password reset', matches: matches, status: 'found', reason: 'semantic_match')
        )
      end

      it 'searches FAQs and returns formatted responses' do
        result = tool.perform(tool_context, query: 'password reset')

        expect(result).to include('Question: How to reset password?')
        expect(result).to include('Answer: Click on forgot password link')
        expect(result).to include('Question: How to change email?')
        expect(result).to include('Answer: Go to settings and update email')
        expect(documentation_searches.first[:status]).to eq('found')
      end

      it 'includes source link when document has external_link' do
        document.update!(external_link: 'https://help.example.com/password')

        result = tool.perform(tool_context, query: 'password')

        expect(result).to include('Source: https://help.example.com/password')
      end

      it 'logs tool usage for search' do
        expect(tool).to receive(:log_tool_usage).with('searching', { query: 'password reset' })
        expect(tool).to receive(:log_tool_usage).with(
          'found_results',
          { query: 'password reset', count: 2, status: 'found', reason: 'semantic_match' }
        )

        tool.perform(tool_context, query: 'password reset')
      end
    end

    context 'when no FAQs found' do
      before do
        allow(documentation_search_service).to receive(:search).and_return(
          search_result(query: 'nonexistent topic', matches: [], status: 'weak', reason: 'no_results')
        )
      end

      it 'returns no results message' do
        result = tool.perform(tool_context, query: 'nonexistent topic')
        expect(result).to include('No relevant FAQs found for: nonexistent topic')
        expect(result).to include('Do not use it to make factual claims')
      end

      it 'logs tool usage for no results' do
        expect(tool).to receive(:log_tool_usage).with('searching', { query: 'nonexistent topic' })
        expect(tool).to receive(:log_tool_usage).with('no_results', { query: 'nonexistent topic' })

        tool.perform(tool_context, query: 'nonexistent topic')
      end
    end

    context 'with blank query' do
      it 'handles empty query' do
        allow(documentation_search_service).to receive(:search).and_return(
          search_result(query: '', matches: [], status: 'weak', reason: 'no_results')
        )

        result = tool.perform(tool_context, query: '')
        expect(result).to include('No relevant FAQs found for: ')
      end
    end
  end

  describe '#active?' do
    it 'returns true for public tools' do
      expect(tool.active?).to be true
    end
  end
end
