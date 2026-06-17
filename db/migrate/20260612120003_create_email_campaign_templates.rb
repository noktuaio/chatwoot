class CreateEmailCampaignTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :email_campaign_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :body_mjml
      t.text :body_html

      t.timestamps
    end

    add_index :email_campaign_templates, [:account_id, :name]
  end
end
