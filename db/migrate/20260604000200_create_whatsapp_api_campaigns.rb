class CreateWhatsappApiCampaigns < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsapp_api_campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :whatsapp_api_message_template, foreign_key: true, index: { name: 'idx_whatsapp_api_campaigns_template_id' }
      t.string :title, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :audience, null: false, default: []
      t.text :message_body
      t.jsonb :template_snapshot, null: false, default: {}
      t.jsonb :media_snapshot, null: false, default: {}
      t.integer :recipients_count, null: false, default: 0
      t.integer :sent_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :cancelled_count, null: false, default: 0
      t.text :last_error_message
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :paused_at
      t.datetime :resumed_at
      t.datetime :completed_at
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :whatsapp_api_campaigns, [:account_id, :status, :scheduled_at], name: 'idx_whatsapp_api_campaigns_account_status'
    add_index :whatsapp_api_campaigns, [:inbox_id, :status, :scheduled_at], name: 'idx_whatsapp_api_campaigns_inbox_status'
  end
end
