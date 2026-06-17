class AllowGlobalEmailCampaignTemplates < ActiveRecord::Migration[7.1]
  def up
    change_column_null :email_campaign_templates, :account_id, true
  end

  def down
    execute 'DELETE FROM email_campaign_templates WHERE account_id IS NULL'
    change_column_null :email_campaign_templates, :account_id, false
  end
end
