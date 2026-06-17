require 'rails_helper'

RSpec.describe WhatsappApiCampaigns::DeliveryJob, type: :job do
  it 'does not process delivery when the feature flag is disabled' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :running)

    allow(WhatsappApiCampaigns::Config).to receive(:enabled?).and_return(false)

    described_class.perform_now(campaign.id)

    expect(Message.where(account_id: account.id).count).to eq(0)
    expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
  end
end
