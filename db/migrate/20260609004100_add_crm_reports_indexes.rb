class AddCrmReportsIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Reports group AI suggestions by status over time (AI auto-move vs human).
    add_index :crm_ai_stage_suggestions, %i[account_id status created_at],
              name: 'idx_crm_ai_suggestions_account_status_created',
              algorithm: :concurrently,
              if_not_exists: true

    # Funnel / win-lost / value reports scan cards per pipeline filtered by
    # status within a closed_at window.
    add_index :crm_cards, %i[account_id pipeline_id status closed_at],
              name: 'idx_crm_cards_account_pipeline_status_closed',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
