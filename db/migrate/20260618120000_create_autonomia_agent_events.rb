class CreateAutonomiaAgentEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :autonomia_agent_events do |t|
      t.references :autonomia_agent, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.bigint  :conversation_id                     # FK lógico (sem constraint — best-effort/log)
      t.integer :event_type, null: false             # enum: replied:0, handed_off:1
      t.float   :confidence                           # nil para handed_off
      t.boolean :answered_from_knowledge, null: false, default: false
      t.string  :handoff_reason                       # nil para replied; motivo CURADO (truncado)
      t.jsonb   :metadata, null: false, default: {}
      t.datetime :created_at, null: false             # só created_at (eventos são imutáveis)
    end
    add_index :autonomia_agent_events, %i[autonomia_agent_id created_at],
              name: 'idx_autonomia_events_agent_created'
    add_index :autonomia_agent_events, %i[autonomia_agent_id event_type],
              name: 'idx_autonomia_events_agent_type'
  end
end
