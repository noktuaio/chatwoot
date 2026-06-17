class AddUniqueOpenCardPerConversationIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # Enforce at most one OPEN card per conversation (status: open = 0), matching the
  # application-level dedup in Crm::Conversations::AutoCreateDeduplicator. Partial +
  # concurrent so it does not lock the live crm_cards table and allows archived/won/lost
  # cards plus a new open card for a reopened conversation.
  def change
    add_index :crm_cards, :conversation_id,
              unique: true,
              where: 'conversation_id IS NOT NULL AND status = 0',
              name: 'idx_crm_cards_unique_open_conversation',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
