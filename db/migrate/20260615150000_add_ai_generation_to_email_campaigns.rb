class AddAiGenerationToEmailCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaigns, :ai_status, :integer, null: false, default: 0
    add_column :email_campaigns, :ai_generation_token, :string
    add_column :email_campaigns, :ai_provider_response_id, :string
    add_column :email_campaigns, :ai_error, :string
    add_column :email_campaigns, :ai_requested_at, :datetime
    add_column :email_campaigns, :ai_completed_at, :datetime
    add_column :email_campaigns, :ai_subject_variants, :jsonb, null: false, default: []
  end
end
