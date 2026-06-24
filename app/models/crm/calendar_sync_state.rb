# Push-notification subscription state for one calendar mailbox (S7-B). See the
# migration for the column semantics. Found by channel_id (the value the provider
# echoes back in its webhook) so an incoming notification resolves to exactly one
# mailbox, and the verification_token authenticates it.
class Crm::CalendarSyncState < ApplicationRecord
  self.table_name = 'crm_calendar_sync_states'

  belongs_to :account
  belongs_to :inbox

  enum provider: { google: 0, microsoft: 1 }
  enum status: { active: 0, expired: 1, failed: 2 }, _prefix: true

  scope :renewable, -> { where(status: :active) }

  # Expiring within the threshold (or already past) — the renewal job re-subscribes.
  def self.expiring_before(time)
    where('expires_at IS NULL OR expires_at <= ?', time)
  end

  def channel
    inbox&.channel
  end
end
