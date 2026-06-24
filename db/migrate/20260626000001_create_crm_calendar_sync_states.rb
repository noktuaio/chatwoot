# Tracks the push-notification subscription (S7-B webhooks) for one calendar
# mailbox. Google: a watch channel (channel_id we generate + resource_id Google
# returns). Microsoft: a Graph subscription (channel_id = subscription id). Both
# carry a shared secret (verification_token = Google channel token / MS clientState)
# used to authenticate the incoming webhook, plus an expiry we renew before. One
# active row per inbox. Additive.
class CreateCrmCalendarSyncStates < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_calendar_sync_states do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :inbox, null: false, foreign_key: true, index: { unique: true }
      t.integer :provider, null: false, default: 0
      t.string :channel_id          # Google watch channel id / MS subscription id
      t.string :resource_id         # Google resource id (nil for MS)
      t.string :verification_token  # shared secret: Google channel token / MS clientState
      t.datetime :expires_at
      t.integer :status, null: false, default: 0
      t.datetime :last_notified_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :crm_calendar_sync_states, :channel_id
    add_index :crm_calendar_sync_states, :expires_at
  end
end
