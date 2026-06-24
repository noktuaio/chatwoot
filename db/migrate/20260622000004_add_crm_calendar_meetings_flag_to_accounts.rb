class AddCrmCalendarMeetingsFlagToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :flags, :bigint, null: false, default: 0, if_not_exists: true
  end
end
