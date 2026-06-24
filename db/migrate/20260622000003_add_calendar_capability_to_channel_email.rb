class AddCalendarCapabilityToChannelEmail < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_email, :calendar_enabled, :boolean, null: false, default: false
    add_column :channel_email, :calendar_scope_granted, :boolean, null: false, default: false
    add_column :channel_email, :calendar_identity, :string

    add_index :channel_email, [:account_id, :calendar_enabled], name: 'idx_channel_email_calendar_enabled'
  end
end
