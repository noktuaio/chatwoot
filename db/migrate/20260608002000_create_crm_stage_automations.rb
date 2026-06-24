class CreateCrmStageAutomations < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_stage_automations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines }
      t.references :stage, null: false, foreign_key: { to_table: :crm_pipeline_stages }
      t.string :name, null: false
      t.text :description
      t.integer :trigger_event, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    create_table :crm_stage_automation_steps do |t|
      t.references :account, null: false, foreign_key: true
      t.references :stage_automation, null: false, foreign_key: { to_table: :crm_stage_automations }
      t.integer :position, null: false, default: 0
      t.integer :delay_seconds, null: false, default: 0
      t.integer :action_type, null: false, default: 0
      t.jsonb :action_config, null: false, default: {}

      t.timestamps
    end

    create_table :crm_stage_automation_executions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: { to_table: :crm_cards }
      t.references :stage_automation, null: false, foreign_key: { to_table: :crm_stage_automations }
      t.string :trigger_token, null: false
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}
      t.datetime :completed_at

      t.timestamps
    end

    add_index :crm_stage_automations, [:account_id, :stage_id, :trigger_event, :position],
              name: 'idx_crm_stage_automations_stage_trigger'
    add_index :crm_stage_automation_steps, [:stage_automation_id, :position],
              name: 'idx_crm_stage_automation_steps_order'
    add_index :crm_stage_automation_executions,
              [:card_id, :stage_automation_id, :trigger_token],
              unique: true,
              name: 'idx_crm_stage_automation_executions_unique'
  end
end
