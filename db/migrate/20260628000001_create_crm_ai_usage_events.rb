class CreateCrmAiUsageEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_ai_usage_events do |t|
      t.bigint :account_id, null: false
      t.bigint :pipeline_id
      t.string :feature, null: false
      t.string :model, null: false
      t.string :reasoning_effort
      t.integer :input_tokens, default: 0, null: false
      t.integer :cached_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.decimal :cost_estimate, precision: 12, scale: 6, default: '0.0', null: false
      t.integer :latency_ms

      t.datetime :created_at, null: false
    end

    add_index :crm_ai_usage_events, %i[account_id created_at], name: 'idx_crm_ai_usage_account_created'
    add_index :crm_ai_usage_events, %i[account_id feature created_at], name: 'idx_crm_ai_usage_account_feature_created'
  end
end
