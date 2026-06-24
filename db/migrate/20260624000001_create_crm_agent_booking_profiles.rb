class CreateCrmAgentBookingProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_agent_booking_profiles do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :inbox, null: false, foreign_key: true, index: true
      t.string :slug, null: false
      t.string :title
      t.text :description
      t.integer :duration_minutes, null: false, default: 30
      t.integer :buffer_minutes, null: false, default: 0
      t.integer :booking_window_days, null: false, default: 14
      # working_hours: { "start_hour": 9, "end_hour": 17, "weekdays": [1,2,3,4,5] }
      t.jsonb :working_hours, null: false, default: {}
      t.string :timezone
      t.boolean :enabled, null: false, default: true
      t.bigint :default_pipeline_id
      t.bigint :default_stage_id
      t.bigint :default_assignee_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crm_agent_booking_profiles, :slug, unique: true
  end
end
