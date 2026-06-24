class CreateEmailEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :email_events do |t|
      t.references :recipient, null: false,
                   foreign_key: { to_table: :email_campaign_recipients }
      # event_type: delivered(0) open(1) click(2) bounce(3) complaint(4) unsubscribe(5)
      t.integer :event_type, null: false
      t.string :url
      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :email_events, [:recipient_id, :event_type],
              name: 'idx_email_events_recipient_type'
    add_index :email_events, :occurred_at, name: 'idx_email_events_occurred_at'
  end
end
