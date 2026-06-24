require 'rails_helper'

RSpec.describe Crm::SyncConversationCardJob, type: :job do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  it 'delegates to the conversation card syncer when enabled' do
    account, user = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Job Lead', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    message = conversation.messages.create!(
      account: account,
      inbox: inbox,
      sender: contact,
      content: 'Oi',
      message_type: :incoming
    )
    syncer = instance_double(Crm::Conversations::CardSyncer, perform: true)

    allow(Crm::Conversations::CardSyncer).to receive(:new).and_return(syncer)

    described_class.perform_now(conversation.id, message.id)

    expect(Crm::Conversations::CardSyncer).to have_received(:new).with(conversation: conversation, message: message)
    expect(syncer).to have_received(:perform)
  end

  it 'does nothing when the CRM feature flag is disabled' do
    ENV['CRM_KANBAN_ENABLED'] = 'false'
    allow(Crm::Conversations::CardSyncer).to receive(:new)

    described_class.perform_now(123, 456)

    expect(Crm::Conversations::CardSyncer).not_to have_received(:new)
  end
end
