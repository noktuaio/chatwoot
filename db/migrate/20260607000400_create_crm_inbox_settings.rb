class CreateCrmInboxSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_inbox_settings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.boolean :crm_enabled, null: false, default: false
      t.references :default_pipeline, foreign_key: { to_table: :crm_pipelines }
      t.references :default_stage, foreign_key: { to_table: :crm_pipeline_stages }
      t.integer :visibility_mode, null: false, default: 0
      t.boolean :auto_create_card, null: false, default: false

      t.timestamps
    end

    add_index :crm_inbox_settings, [:account_id, :inbox_id], unique: true
    add_index :crm_inbox_settings, [:account_id, :crm_enabled]
  end
end
