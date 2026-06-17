class CreateCrmCards < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_cards do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline, null: false, foreign_key: { to_table: :crm_pipelines }
      t.references :stage, null: false, foreign_key: { to_table: :crm_pipeline_stages }
      t.references :contact, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :inbox, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.references :team, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.bigint :value_cents, null: false, default: 0
      t.string :currency, null: false, default: 'BRL'
      t.integer :status, null: false, default: 0
      t.text :lost_reason
      t.string :source
      t.integer :priority, null: false, default: 1
      t.integer :score, null: false, default: 0
      t.datetime :entered_stage_at
      t.datetime :last_activity_at
      t.datetime :last_message_at
      t.datetime :expected_close_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crm_cards, [:account_id, :pipeline_id, :stage_id, :status, :id], name: 'idx_crm_cards_board'
    add_index :crm_cards, [:account_id, :pipeline_id, :stage_id, :status, :inbox_id, :id], name: 'idx_crm_cards_board_inbox'
    add_index :crm_cards, [:account_id, :pipeline_id, :stage_id, :status, :owner_id, :id], name: 'idx_crm_cards_board_owner'
    add_index :crm_cards, [:account_id, :pipeline_id, :stage_id, :status, :team_id, :id], name: 'idx_crm_cards_board_team'
    add_index :crm_cards, [:account_id, :pipeline_id, :stage_id, :status, :priority, :id], name: 'idx_crm_cards_board_priority'
    add_index :crm_cards, [:account_id, :inbox_id, :owner_id], name: 'idx_crm_cards_inbox_owner'
    add_index :crm_cards, [:account_id, :inbox_id, :status, :id], name: 'idx_crm_cards_visible_inbox'
    add_index :crm_cards, [:account_id, :owner_id, :status, :id], name: 'idx_crm_cards_owner'
    add_index :crm_cards, [:account_id, :conversation_id, :status, :id], name: 'idx_crm_cards_conversation'
    add_index :crm_cards, [:account_id, :contact_id], name: 'idx_crm_cards_contact'
    add_index :crm_cards, [:account_id, :entered_stage_at], name: 'idx_crm_cards_entered_stage'
    add_index :crm_cards, [:account_id, :last_message_at], name: 'idx_crm_cards_last_message'
    add_index :crm_cards, [:account_id, :status, :created_at], name: 'idx_crm_cards_status_created'
    add_index :crm_cards, 'lower(title) gin_trgm_ops', name: 'idx_crm_cards_title_trgm', using: :gin
  end
end
