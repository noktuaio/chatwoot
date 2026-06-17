require 'rails_helper'

RSpec.describe CampaignImport do
  it 'allows deletion before import creates contacts' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")

    CampaignImports::Validator.new(campaign_import).perform

    expect(campaign_import.reload).to be_ready_to_confirm
    expect(campaign_import).to be_deletable_before_import
  end

  it 'blocks deletion after contacts were imported' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")
    CampaignImports::Validator.new(campaign_import).perform

    campaign_import.update!(status: :queued)
    CampaignImports::Importer.new(campaign_import.reload).perform

    expect(campaign_import.reload).to be_completed
    expect(campaign_import).not_to be_deletable_before_import
  end
end
