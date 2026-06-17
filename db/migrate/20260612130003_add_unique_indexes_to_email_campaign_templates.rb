class AddUniqueIndexesToEmailCampaignTemplates < ActiveRecord::Migration[7.1]
  def up
    add_index :email_campaign_templates,
              'lower(name)',
              unique: true,
              where: 'account_id IS NULL',
              name: 'index_email_campaign_templates_global_lower_name_unique'

    add_index :email_campaign_templates,
              'account_id, lower(name)',
              unique: true,
              where: 'account_id IS NOT NULL',
              name: 'index_email_campaign_templates_account_lower_name_unique'
  end

  def down
    remove_index :email_campaign_templates, name: 'index_email_campaign_templates_account_lower_name_unique'
    remove_index :email_campaign_templates, name: 'index_email_campaign_templates_global_lower_name_unique'
  end
end
