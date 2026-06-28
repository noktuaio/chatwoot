require 'rails_helper'

RSpec.describe Crm::Ai::UsageBroadcaster do
  before do
    broadcast_calls
    allow(ActionCable.server).to receive(:broadcast) do |stream, message|
      broadcast_calls << [stream, message]
    end
  end

  it 'broadcasts only to users allowed to view CRM reports and never to the account stream', :aggregate_failures do
    account, admin = create_account_and_user
    plain_agent, = create_crm_agent(account: account)
    allowed_role = create(:custom_role, account: account, permissions: ['crm_view_reports'])
    denied_role = create(:custom_role, account: account, permissions: ['crm_view'])
    allowed_custom = create(:user)
    denied_custom = create(:user)
    create(:account_user, account: account, user: allowed_custom, role: :agent, custom_role: allowed_role)
    create(:account_user, account: account, user: denied_custom, role: :agent, custom_role: denied_role)
    event = build(:crm_ai_usage_event, account: account, feature: 'agente_resposta', model: 'gpt-5.4')

    described_class.broadcast(event)

    streams = broadcast_calls.map(&:first)
    expect(streams).to contain_exactly(admin.pubsub_token, plain_agent.pubsub_token, allowed_custom.pubsub_token)
    expect(streams).not_to include(denied_custom.pubsub_token)
    expect(streams).not_to include("account_#{account.id}")
    broadcast_calls.each do |(_, message)|
      expect(message[:event]).to eq('crm.ai_usage.created')
      expect(message[:data]).to include(
        account_id: account.id,
        resource: 'Assistente de respostas',
        input_tokens: event.input_tokens,
        cached_tokens: event.cached_tokens,
        output_tokens: event.output_tokens,
        total_tokens: event.input_tokens + event.output_tokens,
        cost_usd: event.cost_estimate.to_f,
        created_at: event.created_at.iso8601
      )
      expect(message.to_json).not_to include('model')
      expect(message.to_json).not_to include('prompt')
      expect(message.to_json).not_to include('response')
    end
  end

  def broadcast_calls
    @broadcast_calls ||= []
  end
end
