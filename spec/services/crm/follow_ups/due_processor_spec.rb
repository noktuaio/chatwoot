require 'rails_helper'

RSpec.describe Crm::FollowUps::DueProcessor do
  it 'marks due pending follow-ups as overdue and reopens snoozed conversations' do
    account, user = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead Atrasado', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    conversation.update!(status: :snoozed, snoozed_until: 1.hour.ago)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      contact: contact,
      primary_conversation: conversation,
      title: 'Lead Atrasado'
    )
    follow_up = account.crm_follow_ups.create!(
      card: card,
      conversation: conversation,
      title: 'Reabrir',
      due_at: 10.minutes.ago,
      timezone: 'UTC',
      automation_mode: :snooze_conversation,
      created_by: user
    )

    allow(Crm::FollowUps::Broadcaster).to receive(:broadcast_due)

    described_class.new(now: Time.current).perform

    expect(follow_up.reload.status).to eq('overdue')
    expect(conversation.reload.status).to eq('open')
    expect(card.activities.where(event_type: 'follow_up_overdue')).to exist
    expect(Crm::FollowUps::Broadcaster).to have_received(:broadcast_due).with(follow_up)
  end

  it 'sends auto-send follow-ups and marks them done when delivery succeeds' do
    account, user = create_account_and_user
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead Auto', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    template = create_whatsapp_api_template(account: account, inbox: inbox, user: user)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      contact: contact,
      primary_conversation: conversation,
      title: 'Lead Auto'
    )
    follow_up = account.crm_follow_ups.create!(
      card: card,
      conversation: conversation,
      title: 'Enviar mensagem',
      due_at: 10.minutes.ago,
      timezone: 'UTC',
      automation_mode: :auto_send_message,
      created_by: user,
      metadata: {
        message_body: 'Olá, retorno combinado',
        whatsapp_api_message_template_id: template.id
      }
    )

    described_class.new(now: Time.current).perform

    expect(follow_up.reload.status).to eq('done')
    expect(card.activities.where(event_type: 'follow_up_message_sent')).to exist
    expect(card.reload.next_follow_up_at).to be_nil
  end

  it 'marks auto-send follow-ups done when the message was already sent' do
    account, user = create_account_and_user
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead Retry', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    template = create_whatsapp_api_template(account: account, inbox: inbox, user: user)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      contact: contact,
      primary_conversation: conversation,
      title: 'Lead Retry'
    )
    follow_up = account.crm_follow_ups.create!(
      card: card,
      conversation: conversation,
      title: 'Enviar mensagem',
      due_at: 10.minutes.ago,
      timezone: 'UTC',
      automation_mode: :auto_send_message,
      created_by: user,
      metadata: {
        message_body: 'Olá',
        whatsapp_api_message_template_id: template.id,
        sent_message_id: 42
      }
    )

    described_class.new(now: Time.current).perform

    expect(follow_up.reload.status).to eq('done')
  end
end
