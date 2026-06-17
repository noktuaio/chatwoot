require 'rails_helper'

RSpec.describe WhatsappApiCampaigns::DeliveryEngine do
  around do |example|
    previous_value = ENV.fetch('WHATSAPP_API_CAMPAIGNS_ENABLED', nil)
    ENV['WHATSAPP_API_CAMPAIGNS_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('WHATSAPP_API_CAMPAIGNS_ENABLED')
    else
      ENV['WHATSAPP_API_CAMPAIGNS_ENABLED'] = previous_value
    end
  end

  it 'creates exactly one Chatwoot outgoing message per job tick' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    create_labelled_contact(account: account, label: label, name: 'Bia Souza', phone_number: '+5521987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :running)

    described_class.new(campaign).perform

    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.sent.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
  end

  it 'does not duplicate Chatwoot messages when the same campaign is processed again' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :running)

    2.times { described_class.new(campaign).perform }

    message = Message.where(account_id: account.id).first
    recipient = campaign.whatsapp_api_campaign_recipients.first
    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(message.content).to eq('Olá Ana')
    expect(message.additional_attributes['whatsapp_api_campaign_id']).to eq(campaign.id)
    expect(message.conversation.contact).to eq(recipient.contact)
    expect(recipient.reload).to be_sent
    expect(campaign.reload).to be_completed
  end

  it 'does not send while paused' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :paused)

    described_class.new(campaign).perform

    expect(Message.where(account_id: account.id).count).to eq(0)
    expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
  end

  it 'recovers a stale sending recipient and sends it without completing early' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    recipient = campaign.whatsapp_api_campaign_recipients.first
    recipient.update!(status: :sending, attempts: 1, updated_at: 20.minutes.ago)
    campaign.update!(status: :running)

    described_class.new(campaign).perform

    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(recipient.reload).to be_sent
    expect(campaign.reload).to be_completed
  end

  it 'relinks a stale sending recipient to an existing message without creating a duplicate' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    recipient = campaign.whatsapp_api_campaign_recipients.first
    campaign.update!(status: :running)

    message = WhatsappApiCampaigns::ConversationRecorder.new(recipient: recipient, rendered_body: 'Olá Ana').perform
    recipient.update_columns(status: WhatsappApiCampaignRecipient.statuses[:sending],
                             message_id: nil,
                             conversation_id: nil,
                             attempts: 1,
                             updated_at: 20.minutes.ago)

    described_class.new(campaign).perform

    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(recipient.reload).to be_sent
    expect(recipient.message_id).to eq(message.id)
  end

  it 'does not complete while a non-stale sending recipient is still in flight' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    recipient = campaign.whatsapp_api_campaign_recipients.first
    recipient.update!(status: :sending, attempts: 1)
    campaign.update!(status: :running)

    described_class.new(campaign).perform

    expect(campaign.reload).to be_running
    expect(recipient.reload).to be_sending
    expect(Message.where(account_id: account.id).count).to eq(0)
  end

  it 'sends once when two contacts share the same phone' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    duplicate = create_labelled_contact(account: account, label: label, name: 'Ana Duplicada', phone_number: '+5511987654322')
    duplicate.update_columns(phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :running)

    2.times { described_class.new(campaign).perform }

    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.sent.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.failed.count).to eq(1)
    expect(campaign.reload).to be_completed_with_failures
  end
end
