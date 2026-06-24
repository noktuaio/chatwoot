class CreateCrmMeetings < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_meetings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: { to_table: :crm_cards }
      t.references :inbox, null: true, foreign_key: { on_delete: :nullify }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :reminder, foreign_key: { to_table: :crm_follow_ups, on_delete: :nullify }

      t.string :title, null: false
      t.text :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :timezone, null: false, default: 'UTC'
      t.integer :status, null: false, default: 0
      t.integer :provider, null: false
      t.integer :online_meeting_type, null: false, default: 0
      t.string :external_event_id
      t.text :online_meeting_url
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crm_meetings, [:account_id, :card_id], name: 'idx_crm_meetings_card'
    add_index :crm_meetings, [:account_id, :inbox_id], name: 'idx_crm_meetings_inbox'
    add_index :crm_meetings, [:account_id, :created_by_id], name: 'idx_crm_meetings_created_by'
    add_index :crm_meetings, [:account_id, :status], name: 'idx_crm_meetings_status'
    add_index :crm_meetings, [:account_id, :starts_at], name: 'idx_crm_meetings_starts_at'
    add_index :crm_meetings, [:external_event_id, :provider],
              unique: true, where: 'external_event_id IS NOT NULL', name: 'idx_crm_meetings_external_unique'
  end
end
