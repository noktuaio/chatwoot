class CreateCrmPipelineInboxes < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_pipeline_inboxes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines }
      t.references :inbox, null: false, foreign_key: true
      t.references :default_stage, foreign_key: { to_table: :crm_pipeline_stages }
      t.boolean :auto_create_card, null: false, default: false
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :crm_pipeline_inboxes, [:account_id, :pipeline_id, :inbox_id],
              unique: true, name: 'idx_crm_pipeline_inboxes_unique'
    add_index :crm_pipeline_inboxes, [:account_id, :inbox_id]
  end
end
