require 'rails_helper'

RSpec.describe Crm::Card, type: :model do
  it 'allows standalone cards without contact, conversation or inbox' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)

    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Renovação interna')

    expect(card).to be_persisted
    expect(card.contact_id).to be_nil
    expect(card.conversation_id).to be_nil
    expect(card.inbox_id).to be_nil
    expect(card).to be_standalone
  end

  it 'rejects linked records from another account' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    other_account, = create_account_and_user
    other_contact = other_account.contacts.create!(name: 'Outro contato', phone_number: '+5511987654321')

    card = account.crm_cards.new(pipeline: pipeline, stage: stage, contact: other_contact, title: 'Vazamento')

    expect(card).not_to be_valid
    expect(card.errors[:contact]).to include('must belong to the same account')
  end

  it 'requires the stage to belong to the selected pipeline' do
    account, user = create_account_and_user
    first_pipeline, = create_crm_pipeline(account: account, user: user, name: 'Primeiro')
    second_pipeline, second_stage = create_crm_pipeline(account: account, user: user, name: 'Segundo')

    card = account.crm_cards.new(pipeline: first_pipeline, stage: second_stage, title: 'Etapa errada')

    expect(card).not_to be_valid
    expect(card.errors[:stage]).to include('must belong to the selected pipeline')
    expect(second_pipeline).to be_present
  end
end
