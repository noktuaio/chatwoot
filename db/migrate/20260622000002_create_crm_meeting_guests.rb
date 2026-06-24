class CreateCrmMeetingGuests < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_meeting_guests do |t|
      t.references :account, null: false, foreign_key: true
      t.references :meeting, null: false, foreign_key: { to_table: :crm_meetings }
      t.references :contact, foreign_key: true
      t.references :user, foreign_key: true

      t.string :email, null: false
      t.string :name
      t.integer :guest_type, null: false, default: 0
      t.integer :rsvp_status, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crm_meeting_guests, [:account_id, :meeting_id], name: 'idx_crm_meeting_guests_meeting'
    add_index :crm_meeting_guests, [:account_id, :meeting_id, :email],
              unique: true, name: 'idx_crm_meeting_guests_unique_email'
    add_index :crm_meeting_guests, :contact_id, name: 'idx_crm_meeting_guests_contact'
  end
end
