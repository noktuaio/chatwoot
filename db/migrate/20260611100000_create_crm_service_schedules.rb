class CreateCrmServiceSchedules < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_service_schedules do |t|
      t.bigint :account_id, null: false, index: true
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.string :timezone, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :blocks, null: false, default: []
      t.timestamps
    end

    add_index :crm_service_schedules, [:account_id, :owner_type, :owner_id], unique: true, name: 'idx_crm_service_schedules_owner_unique'
    add_index :crm_service_schedules, [:owner_type, :owner_id]
  end
end
