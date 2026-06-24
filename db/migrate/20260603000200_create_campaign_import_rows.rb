class CreateCampaignImportRows < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_import_rows do |t|
      t.bigint :campaign_import_id, null: false
      t.integer :row_number, null: false
      t.string :raw_name
      t.string :raw_phone_masked
      t.string :normalized_name
      t.string :normalized_phone_hash
      t.bigint :contact_id
      t.boolean :was_existing_contact, default: false, null: false
      t.jsonb :labels_applied, default: [], null: false
      t.integer :batch_index
      t.integer :status, default: 0, null: false
      t.jsonb :error_messages, default: [], null: false

      t.timestamps
    end

    add_index :campaign_import_rows, :campaign_import_id
    add_index :campaign_import_rows, [:campaign_import_id, :row_number], unique: true, name: 'idx_campaign_import_rows_on_import_and_row_number'
    add_index :campaign_import_rows, :normalized_phone_hash
    add_index :campaign_import_rows, :contact_id
    add_index :campaign_import_rows, [:campaign_import_id, :status]
  end
end
