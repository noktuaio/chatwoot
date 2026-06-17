require 'rails_helper'

RSpec.describe CampaignImports::ValidateJob, type: :job do
  it 'does not run validation when the feature flag is disabled' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\n")

    allow(CampaignImports::Config).to receive(:enabled?).and_return(false)
    expect(CampaignImports::Validator).not_to receive(:new)

    described_class.perform_now(campaign_import)

    expect(campaign_import.reload).to be_uploaded
  end
end
