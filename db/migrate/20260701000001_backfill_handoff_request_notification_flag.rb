# Turns ON the email + push bit for the new `conversation_handoff_request`
# notification type (enum value 10 -> FlagShihTzu bit 2**(10-1) = 512) for all
# existing notification settings. Without this backfill the R3 handoff invite is
# recorded but delivers no push/email — an invite nobody sees. New users get the
# bit from AccountUser#create_notification_setting defaults.
class BackfillHandoffRequestNotificationFlag < ActiveRecord::Migration[7.1]
  HANDOFF_REQUEST_BIT = 512

  def up
    execute(<<~SQL.squish)
      UPDATE notification_settings
      SET email_flags = email_flags | #{HANDOFF_REQUEST_BIT},
          push_flags  = push_flags  | #{HANDOFF_REQUEST_BIT}
    SQL
  end

  def down
    execute(<<~SQL.squish)
      UPDATE notification_settings
      SET email_flags = email_flags & ~#{HANDOFF_REQUEST_BIT},
          push_flags  = push_flags  & ~#{HANDOFF_REQUEST_BIT}
    SQL
  end
end
