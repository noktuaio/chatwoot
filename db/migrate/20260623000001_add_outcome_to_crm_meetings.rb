class AddOutcomeToCrmMeetings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_meetings, :outcome, :integer
    add_column :crm_meetings, :outcome_notes, :text
    add_column :crm_meetings, :outcome_recorded_at, :datetime
    # Composite index for the no-show KPI (per-account, by outcome + recorded date).
    add_index :crm_meetings, [:account_id, :outcome, :outcome_recorded_at]
  end
end
