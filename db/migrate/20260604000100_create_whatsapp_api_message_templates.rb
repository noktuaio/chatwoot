class CreateWhatsappApiMessageTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsapp_api_message_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :body, null: false
      t.jsonb :variables, null: false, default: []
      t.datetime :archived_at

      t.timestamps
    end

    add_index :whatsapp_api_message_templates,
              [:account_id, :inbox_id, :name],
              unique: true,
              where: 'archived_at IS NULL',
              name: 'idx_whatsapp_api_templates_active_name'
    add_index :whatsapp_api_message_templates, [:account_id, :inbox_id, :archived_at], name: 'idx_whatsapp_api_templates_inbox'
  end
end
