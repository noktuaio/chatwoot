class CreateCrmPipelineStages < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_pipeline_stages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines }
      t.string :name, null: false
      t.text :description
      t.string :color
      t.integer :position, null: false, default: 0
      t.integer :win_probability, null: false, default: 0
      t.integer :wip_limit
      t.integer :sla_seconds
      t.integer :sla_warning_seconds
      t.boolean :is_won_stage, null: false, default: false
      t.boolean :is_lost_stage, null: false, default: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crm_pipeline_stages, [:account_id, :pipeline_id, :position], name: 'idx_crm_stages_account_pipeline_position'
    add_index :crm_pipeline_stages, [:account_id, :pipeline_id]
  end
end
