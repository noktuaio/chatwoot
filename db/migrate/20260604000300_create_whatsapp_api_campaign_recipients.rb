class CreateWhatsappApiCampaignRecipients < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsapp_api_campaign_recipients do |t|
      t.references :whatsapp_api_campaign, null: false, foreign_key: true, index: { name: 'idx_wa_api_recipients_campaign_id' }
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :message, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.string :phone_mask
      t.string :phone_hash
      t.string :rendered_body_sha256
      t.string :provider_message_id
      t.text :last_error_message
      t.datetime :started_at
      t.datetime :sent_at
      t.datetime :failed_at
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :whatsapp_api_campaign_recipients,
              [:whatsapp_api_campaign_id, :contact_id],
              unique: true,
              name: 'idx_wa_api_recipients_campaign_contact'
    add_index :whatsapp_api_campaign_recipients,
              [:whatsapp_api_campaign_id, :message_id],
              unique: true,
              where: 'message_id IS NOT NULL',
              name: 'idx_wa_api_recipients_campaign_message'
    add_index :whatsapp_api_campaign_recipients, [:whatsapp_api_campaign_id, :status], name: 'idx_wa_api_recipients_campaign_status'
    add_index :whatsapp_api_campaign_recipients, [:inbox_id, :status, :created_at], name: 'idx_wa_api_recipients_inbox_status'
  end
end
