class CreateCrmActivities < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_activities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: { to_table: :crm_cards }
      t.references :conversation, foreign_key: true
      t.string :actor_type
      t.bigint :actor_id
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :crm_activities, [:account_id, :card_id, :created_at], name: 'idx_crm_activities_card_time'
    add_index :crm_activities, [:account_id, :event_type, :created_at], name: 'idx_crm_activities_event_time'
  end
end
