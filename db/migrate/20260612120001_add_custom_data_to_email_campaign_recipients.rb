class AddCustomDataToEmailCampaignRecipients < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaign_recipients, :custom_data, :jsonb, null: false, default: {}
  end
end
