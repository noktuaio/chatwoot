class CreateCampaignImports < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_imports do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.bigint :data_import_id
      t.integer :status, default: 0, null: false
      t.integer :undo_status, default: 0, null: false
      t.string :source_filename
      t.string :source_content_type
      t.string :source_format
      t.bigint :source_byte_size
      t.integer :total_rows, default: 0, null: false
      t.integer :valid_rows, default: 0, null: false
      t.integer :invalid_rows, default: 0, null: false
      t.integer :duplicate_file_rows, default: 0, null: false
      t.integer :imported_contacts_count, default: 0, null: false
      t.integer :existing_contacts_count, default: 0, null: false
      t.integer :failed_contacts_count, default: 0, null: false
      t.integer :new_contacts_estimate, default: 0, null: false
      t.integer :processed_records, default: 0, null: false
      t.integer :failed_records, default: 0, null: false
      t.integer :new_contacts_count, default: 0, null: false
      t.integer :existing_contacts_updated_count, default: 0, null: false
      t.string :mode
      t.string :campaign_name
      t.string :campaign_slug
      t.string :base_label
      t.integer :batch_count, default: 0, null: false
      t.jsonb :labels_payload, default: {}, null: false
      t.jsonb :validation_summary, default: {}, null: false
      t.jsonb :options, default: {}, null: false
      t.datetime :started_at
      t.datetime :validated_at
      t.datetime :confirmed_at
      t.datetime :queued_at
      t.datetime :import_started_at
      t.datetime :import_finished_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.datetime :undo_started_at
      t.datetime :undo_finished_at
      t.datetime :undo_completed_at

      t.timestamps
    end

    add_index :campaign_imports, :account_id
    add_index :campaign_imports, :user_id
    add_index :campaign_imports, :data_import_id
    add_index :campaign_imports, [:account_id, :status]
    add_index :campaign_imports, [:account_id, :created_at]
    add_index :campaign_imports, [:account_id, :campaign_slug]
  end
end
