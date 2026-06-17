require 'rails_helper'

RSpec.describe Crm::CardPolicy, type: :policy do
  it 'allows admins to see all cards in the account' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Admin vê')

    scope = described_class::Scope.new(policy_context(account, admin), Crm::Card).resolve

    expect(scope).to include(card)
  end

  it 'hides inbox cards from agents without inbox membership' do
    account, admin = create_account_and_user
    agent, agent_account_user = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, title: 'Privado')

    scope = described_class::Scope.new(policy_context(account, agent, agent_account_user), Crm::Card).resolve

    expect(scope).not_to include(card)
  end

  it 'enforces assigned_only visibility for inbox cards' do
    account, admin = create_account_and_user
    agent, agent_account_user = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, visibility_mode: :assigned_only)
    hidden_card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, title: 'Sem dono')
    visible_card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, owner: agent, title: 'Meu card')

    scope = described_class::Scope.new(policy_context(account, agent, agent_account_user), Crm::Card).resolve

    expect(scope).not_to include(hidden_card)
    expect(scope).to include(visible_card)
  end

  it 'shows standalone cards only to their owner when the user is an agent' do
    account, admin = create_account_and_user
    agent, agent_account_user = create_crm_agent(account: account)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    owned = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, title: 'Meu avulso')
    unowned = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Avulso sem dono')

    scope = described_class::Scope.new(policy_context(account, agent, agent_account_user), Crm::Card).resolve

    expect(scope).to include(owned)
    expect(scope).not_to include(unowned)
  end

  def policy_context(account, user, account_user = nil)
    {
      account: account,
      user: user,
      account_user: account_user || account.account_users.find_by(user_id: user.id)
    }
  end
end
