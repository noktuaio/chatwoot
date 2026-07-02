require 'rails_helper'

RSpec.describe Crm::Cards::PayloadBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:account_user) { admin.account_users.find_by(account: account) }
  let(:contact) { create(:contact, account: account) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  def build_card(ai_meta)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      contact: contact,
      title: 'Lead badge',
      metadata: { 'ai' => ai_meta }
    )
  end

  def payload_for(card)
    visibility = Crm::Conversations::Visibility.new(account: account, user: admin, account_user: account_user)
    described_class.new(card, user: admin, account_user: account_user, conversation_visibility: visibility).perform
  end

  it 'exposes handoff_invite with epochs for an open invite cycle' do
    invited_at = 5.minutes.ago.change(usec: 0)
    due_at = invited_at + 15.minutes
    card = build_card(
      'handoff' => {
        'cycle_id' => 1, 'invited_at' => invited_at.iso8601,
        'pickup_due_at' => due_at.iso8601, 'invited_agent_id' => admin.id
      }
    )

    invite = payload_for(card)[:handoff_invite]

    expect(invite[:invited_at]).to eq(invited_at.to_i)
    expect(invite[:pickup_due_at]).to eq(due_at.to_i)
  end

  it 'derives pickup_due_at from the effective threshold for legacy cycles' do
    invited_at = 5.minutes.ago.change(usec: 0)
    card = build_card(
      'handoff' => { 'cycle_id' => 1, 'invited_at' => invited_at.iso8601, 'invited_agent_id' => admin.id }
    )

    invite = payload_for(card)[:handoff_invite]

    expect(invite[:pickup_due_at]).to eq((invited_at + 900.seconds).to_i)
  end

  it 'omits handoff_invite once the cycle is picked up' do
    card = build_card(
      'handoff' => {
        'cycle_id' => 1, 'invited_at' => 20.minutes.ago.iso8601,
        'picked_up_at' => 5.minutes.ago.iso8601, 'invited_agent_id' => admin.id
      }
    )

    expect(payload_for(card)[:handoff_invite]).to be_nil
  end
end
