class AddClosedAtToCrmCards < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_cards, :closed_at, :datetime

    # Backfill existing won/lost cards so period-based win/lost and cycle-time
    # KPIs are correct from day one. Idempotent: only fills NULLs.
    # status: won=1, lost=2 (see Crm::Card enum).
    execute(<<~SQL.squish)
      UPDATE crm_cards
      SET closed_at = updated_at
      WHERE status IN (1, 2) AND closed_at IS NULL
    SQL
  end

  def down
    remove_column :crm_cards, :closed_at
  end
end
