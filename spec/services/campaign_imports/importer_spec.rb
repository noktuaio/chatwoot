require 'rails_helper'

RSpec.describe CampaignImports::Importer do
  it 'creates contacts, creates hidden labels, applies one batch label, and supports undo' do
    account, user = create_account_and_user
    existing_contact = account.contacts.create!(name: 'Manual', phone_number: '+5511987654321')
    existing_contact.label_list.add('manual')
    existing_contact.save!
    content = "nome,telefone\nAna,11987654321\nBia,21987654321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 2)
    CampaignImports::Validator.new(campaign_import).perform

    campaign_import.update!(status: :queued)
    described_class.new(campaign_import.reload).perform

    expect(campaign_import.reload).to be_completed
    expect(account.contacts.count).to eq(2)
    expect(account.labels.where(show_on_sidebar: false).pluck(:title)).to include(campaign_import.base_label)
    expect(existing_contact.reload.label_list).to include('manual', campaign_import.base_label)
    expect(campaign_import.campaign_import_rows.status_imported.count).to eq(2)
    expect(campaign_import.campaign_import_rows.pluck(:labels_applied).flatten.uniq).to include(campaign_import.base_label)

    described_class.new(campaign_import.reload).perform

    expect(account.contacts.count).to eq(2)
    expect(campaign_import.reload).to be_completed

    CampaignImports::UndoLabels.new(campaign_import).perform

    expect(campaign_import.reload).to be_labels_undone
    expect(existing_contact.reload.label_list).to include('manual')
    expect(existing_contact.label_list).not_to include(campaign_import.base_label)
    expect(account.contacts.count).to eq(2)

    CampaignImports::UndoLabels.new(campaign_import.reload).perform

    expect(campaign_import.reload).to be_labels_undone
    expect(account.contacts.count).to eq(2)
  end
end
