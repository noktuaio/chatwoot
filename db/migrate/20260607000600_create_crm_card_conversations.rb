class CreateCrmCardConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_card_conversations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: { to_table: :crm_cards }
      t.references :conversation, null: false, foreign_key: true
      t.boolean :is_primary, null: false, default: false
      t.references :linked_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :crm_card_conversations, [:account_id, :card_id], name: 'idx_crm_card_conversations_card'
    add_index :crm_card_conversations, [:account_id, :conversation_id], name: 'idx_crm_card_conversations_conversation'
    add_index :crm_card_conversations, [:account_id, :card_id, :conversation_id],
              unique: true, name: 'idx_crm_card_conversations_unique'
  end
end
