require 'rails_helper'

RSpec.describe Crm::AiUsageEvent, type: :model do
  it 'registers usage broadcasting as an after create commit callback' do
    callback = described_class._commit_callbacks.find { |item| item.filter == :broadcast_usage_created }

    expect(callback).to be_present
    expect(callback.kind).to eq(:after)
    expect(callback.instance_variable_get(:@name)).to eq(:commit)
    expect(callback.instance_variable_get(:@if)).to be_present
  end

  it 'delegates the post-commit broadcast to the usage broadcaster' do
    event = build(:crm_ai_usage_event)
    allow(Crm::Ai::UsageBroadcaster).to receive(:broadcast)

    event.send(:broadcast_usage_created)

    expect(Crm::Ai::UsageBroadcaster).to have_received(:broadcast).with(event)
  end
end
