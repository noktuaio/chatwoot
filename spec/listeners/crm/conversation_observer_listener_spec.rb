require 'rails_helper'

RSpec.describe Crm::ConversationObserverListener do
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

  it 'enqueues conversation card sync for a real chat message' do
    account, user = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Listener Lead', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    message = create_message(conversation: conversation, sender: contact)
    clear_enqueued_jobs

    described_class.instance.message_created(event_for(message))

    expect(Crm::SyncConversationCardJob).to have_been_enqueued.with(conversation.id, message.id)
  end

  it 'ignores private notes and activity messages' do
    account, user = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Listener Ignorado', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    private_message = create_message(conversation: conversation, sender: user, message_type: :outgoing, private: true)
    activity_message = create_message(conversation: conversation, sender: user, message_type: :activity)
    clear_enqueued_jobs

    described_class.instance.message_created(event_for(private_message))
    described_class.instance.message_created(event_for(activity_message))

    expect(Crm::SyncConversationCardJob).not_to have_been_enqueued
  end

  it 'does not enqueue when the CRM feature flag is disabled' do
    account, user = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Listener Flag', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    message = create_message(conversation: conversation, sender: contact)
    clear_enqueued_jobs
    ENV['CRM_KANBAN_ENABLED'] = 'false'

    described_class.instance.message_created(event_for(message))

    expect(Crm::SyncConversationCardJob).not_to have_been_enqueued
  end

  def event_for(message)
    instance_double(Events::Base, data: { message: message })
  end

  def create_message(conversation:, sender:, content: 'Oi', message_type: :incoming, private: false)
    conversation.messages.create!(
      account: conversation.account,
      inbox: conversation.inbox,
      sender: sender,
      content: content,
      message_type: message_type,
      private: private
    )
  end
end
