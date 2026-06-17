require 'rails_helper'

RSpec.describe CampaignImports::Validator do
  it 'rejects duplicate phones and writes an error CSV without importing contacts' do
    account, user = create_account_and_user
    content = "nome,telefone\nAna,11987654321\nBia,(11) 98765-4321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content)

    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_validation_failed
    expect(account.contacts.count).to eq(0)
    expect(campaign_import.campaign_import_rows.status_invalid.count).to eq(2)
    expect(campaign_import.error_csv.download).to include('duplicate_phone_in_file')
    expect(campaign_import.error_csv.download).not_to include('11987654321')
  end

  it 'marks a valid file ready to confirm and stores only masked phones in rows' do
    account, user = create_account_and_user
    content = "nome,telefone\nAna,11987654321\nBia,21987654321\nCaio,31987654321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 2)

    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_ready_to_confirm
    expect(campaign_import.campaign_import_rows.status_valid.count).to eq(3)
    expect(campaign_import.campaign_import_rows.pluck(:raw_phone_masked).join).not_to include('11987654321')
    expect(campaign_import.normalized_csv.download).to include('phone_hash')
    expect(campaign_import.campaign_import_labels.kind_batch.order(:batch_index).pluck(:planned_count)).to eq([1, 2])
  end
end
