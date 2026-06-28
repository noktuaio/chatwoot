require 'rails_helper'

RSpec.describe Crm::AiUsageEvent, type: :model do
  def build_event(account:, **attrs)
    Crm::AiUsageEvent.create!(
      {
        account_id: account.id,
        feature: 'agente_resposta',
        model: 'gpt-5.4-mini',
        input_tokens: 0,
        cached_tokens: 0,
        output_tokens: 0,
        cost_estimate: 0,
        created_at: Time.current
      }.merge(attrs)
    )
  end

  it 'requires feature and model' do
    account, = create_account_and_user

    event = described_class.new(account_id: account.id)
    expect(event).not_to be_valid
    expect(event.errors.attribute_names).to include(:feature, :model)
  end

  it 'belongs to an account' do
    event = described_class.new(feature: 'copilot', model: 'gpt-5.4-mini')
    expect(event).not_to be_valid
    expect(event.errors.attribute_names).to include(:account)
  end

  describe '.spend_by_feature' do
    it 'aggregates calls, cost and tokens per feature' do
      account, = create_account_and_user
      build_event(account: account, feature: 'agente_resposta', input_tokens: 100, output_tokens: 50, cost_estimate: 0.01)
      build_event(account: account, feature: 'agente_resposta', input_tokens: 200, cached_tokens: 40, output_tokens: 60, cost_estimate: 0.02)
      build_event(account: account, feature: 'copilot', input_tokens: 10, output_tokens: 5, cost_estimate: 0.001)

      summary = described_class.spend_by_feature(described_class.for_account(account.id))

      expect(summary['agente_resposta'][:calls]).to eq(2)
      expect(summary['agente_resposta'][:input_tokens]).to eq(300)
      expect(summary['agente_resposta'][:cached_tokens]).to eq(40)
      expect(summary['agente_resposta'][:output_tokens]).to eq(110)
      expect(summary['agente_resposta'][:cost].to_f).to be_within(1e-9).of(0.03)
      expect(summary['copilot'][:calls]).to eq(1)
    end
  end

  describe 'scopes' do
    it 'filters by account with .for_account' do
      account_a, = create_account_and_user
      account_b, = create_account_and_user
      build_event(account: account_a)
      build_event(account: account_b)

      expect(described_class.for_account(account_a.id).count).to eq(1)
    end

    it 'filters by time with .since' do
      account, = create_account_and_user
      build_event(account: account, created_at: 2.days.ago)
      build_event(account: account, created_at: Time.current)

      expect(described_class.for_account(account.id).since(1.day.ago).count).to eq(1)
    end
  end
end
