require 'rails_helper'

RSpec.describe WhatsappApiCampaigns::AudienceResolver do
  it 'creates one durable recipient per labelled contact and stores masked phone only' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    create_labelled_contact(account: account, label: label, name: 'Sem Telefone', phone_number: nil)
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

    described_class.new(campaign).perform

    expect(campaign.whatsapp_api_campaign_recipients.count).to eq(2)
    expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.failed.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.first.phone_mask).not_to include('987654321')
    expect(campaign.reload.recipients_count).to eq(2)
  end

  it 'marks duplicate phones as failed so the campaign sends only once to a number' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    duplicate = create_labelled_contact(account: account, label: label, name: 'Ana Duplicada', phone_number: '+5511987654322')
    duplicate.update_columns(phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

    described_class.new(campaign).perform

    expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.failed.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.failed.first.last_error_message).to eq('duplicate_phone_number')
  end
end
