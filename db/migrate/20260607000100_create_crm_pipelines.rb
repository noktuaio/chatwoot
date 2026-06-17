class CreateCrmPipelines < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_pipelines do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.boolean :is_default, null: false, default: false
      t.integer :position, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crm_pipelines, [:account_id, :status]
    add_index :crm_pipelines, [:account_id, :position]
    add_index :crm_pipelines, [:account_id, :is_default]
  end
end
