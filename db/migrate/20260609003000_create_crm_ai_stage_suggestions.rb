class CreateCrmAiStageSuggestions < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_ai_stage_suggestions do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :card, null: false, foreign_key: { to_table: :crm_cards }, index: true
      t.references :from_stage, null: false, foreign_key: { to_table: :crm_pipeline_stages }
      t.references :to_stage, null: false, foreign_key: { to_table: :crm_pipeline_stages }
      t.decimal :confidence, precision: 5, scale: 4, null: false
      t.string :reasoning, limit: 500
      t.string :model_used, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :crm_ai_stage_suggestions, [:card_id, :status, :created_at], name: 'idx_crm_ai_suggestions_card_status_created'
  end
end
