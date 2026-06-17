class CreateAutonomiaAgentInboxes < ActiveRecord::Migration[7.1]
  def change
    create_table :autonomia_agent_inboxes do |t|
      t.references :autonomia_agent, null: false, foreign_key: true
      t.references :inbox,   null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true
      # AgentBot nativo-espelho (sender canônico da resposta outgoing). NON-NULL + FK:
      # sem ele a Message perde a identidade de AgentBot-sender (garantia anti-loop).
      t.references :agent_bot, null: false, foreign_key: true
      t.timestamps
    end
    add_index :autonomia_agent_inboxes, :inbox_id, unique: true,
              name: 'idx_autonomia_agent_inboxes_on_inbox_uniq' # um bot por inbox
  end
end
