class CreateEmailCampaignRecipients < ActiveRecord::Migration[7.1]
  def change
    create_table :email_campaign_recipients do |t|
      t.references :email_campaign, null: false, foreign_key: true
      t.string :name
      t.string :email, null: false
      # status: pending(0) sent(1) failed(2) suppressed(3)
      t.integer :status, null: false, default: 0
      t.string :ses_message_id
      t.datetime :sent_at
      t.text :last_error

      t.timestamps
    end

    add_index :email_campaign_recipients,
              'email_campaign_id, lower(email)',
              unique: true,
              name: 'idx_email_campaign_recipients_campaign_email'
    add_index :email_campaign_recipients, [:email_campaign_id, :status],
              name: 'idx_email_campaign_recipients_campaign_status'
  end
end
