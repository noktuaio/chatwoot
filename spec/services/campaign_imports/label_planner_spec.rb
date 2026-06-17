require 'rails_helper'

RSpec.describe CampaignImports::LabelPlanner do
  it 'creates hidden-safe base and batch label plans with a smaller first batch' do
    account, user = create_account_and_user
    campaign_import = account.campaign_imports.create!(
      user: user,
      status: :uploaded,
      mode: 'batches',
      campaign_name: 'Campanha Ágil',
      batch_count: 3
    )

    plan = described_class.new(campaign_import, total_rows: 10).perform

    expect(plan.base_label).to match(/\Acampanha_campanha_agil_\d+\z/)
    expect(plan.batch_sizes).to eq([2, 4, 4])
    expect(campaign_import.campaign_import_labels.kind_batch.order(:batch_index).pluck(:planned_count)).to eq([2, 4, 4])
  end
end
