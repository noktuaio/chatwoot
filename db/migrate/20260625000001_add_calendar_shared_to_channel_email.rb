# Marks a calendar-enabled mailbox as SHARED by several agents (e.g. a single
# comercial@ used by 10 sellers). When true, availability is computed PER AGENT
# from the CRM's own meetings instead of the mailbox free/busy (which would be the
# union of everyone and over-block). Default false = current behaviour (real
# provider free/busy), so existing setups are unchanged.
class AddCalendarSharedToChannelEmail < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_email, :calendar_shared, :boolean, default: false, null: false
  end
end
