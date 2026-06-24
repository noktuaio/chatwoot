require 'rails_helper'

RSpec.describe CampaignImports::PurgeExpiredFilesJob, type: :job do
  it 'purges expired attachments based on attachment creation time and keeps records' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\n")
    campaign_import.report_csv.attach(io: StringIO.new('metric,value'), filename: 'report.csv', content_type: 'text/csv')
    campaign_import.original_file_attachment.update!(created_at: 8.days.ago)
    campaign_import.report_csv_attachment.update!(created_at: 31.days.ago)

    expect do
      described_class.perform_now
    end.to have_enqueued_job(ActiveStorage::PurgeJob).twice

    expect(CampaignImport.exists?(campaign_import.id)).to be(true)
  end
end
