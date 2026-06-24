class CreateCrmFollowUps < ActiveRecord::Migration[7.1]
  def change
    create_crm_follow_ups_table
    add_crm_follow_up_card_column
    add_crm_follow_up_indexes
  end

  private

  def create_crm_follow_ups_table
    create_table :crm_follow_ups do |t|
      add_follow_up_references(t)
      t.string :title, null: false
      t.text :description
      t.integer :follow_up_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :automation_mode, null: false, default: 0
      t.datetime :due_at, null: false
      t.string :timezone, null: false, default: 'UTC'
      t.datetime :completed_at
      t.datetime :canceled_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end

  def add_follow_up_references(table)
    table.references :account, null: false, foreign_key: true
    table.references :card, null: false, foreign_key: { to_table: :crm_cards }
    table.references :conversation, foreign_key: true
    table.references :contact, foreign_key: true
    table.references :inbox, foreign_key: true
    table.references :assignee, foreign_key: { to_table: :users }
  end

  def add_crm_follow_up_card_column
    add_column :crm_cards, :next_follow_up_at, :datetime
  end

  def add_crm_follow_up_indexes
    add_index :crm_follow_ups, [:account_id, :assignee_id, :due_at, :status], name: 'idx_crm_followups_assignee_due'
    add_index :crm_follow_ups, [:account_id, :card_id], name: 'idx_crm_followups_card'
    add_index :crm_follow_ups, [:account_id, :conversation_id], name: 'idx_crm_followups_conversation'
    add_index :crm_follow_ups, [:account_id, :status, :due_at], name: 'idx_crm_followups_status_due'
    add_index :crm_follow_ups, [:status, :due_at, :id], name: 'idx_crm_followups_due_processor'
    add_index :crm_cards, [:account_id, :next_follow_up_at], name: 'idx_crm_cards_next_follow_up'
    add_index :crm_cards, [:account_id, :pipeline_id, :expected_close_at, :id], name: 'idx_crm_cards_calendar'
    add_index :crm_cards, [:account_id, :pipeline_id, :stage_id, :status, :next_follow_up_at, :id], name: 'idx_crm_cards_board_follow_up'
    add_index :crm_cards, [:account_id, :updated_at, :id], name: 'idx_crm_cards_account_updated'
  end
end
