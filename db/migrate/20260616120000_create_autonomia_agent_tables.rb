class CreateAutonomiaAgentTables < ActiveRecord::Migration[7.0]
  def change
    create_agents
    create_sources
    create_knowledge
    create_build_threads
  end

  private

  def create_agents
    create_table :autonomia_agents do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :agent_type, null: false, default: 'support' # support|sdr|reception|onboarding|scheduler|reactivation|custom
      t.integer :status, null: false, default: 0 # enum: draft:0, active:1, paused:2
      t.integer :mode,   null: false, default: 0 # enum: guided:0, manual:1
      t.text    :instruction      # OCULTO (IP) — nunca no jbuilder
      t.text    :scaffold         # OCULTO (andaime/guardrails) — nunca no jbuilder
      t.text    :human_card       # visível: resumo humano
      t.text    :greeting
      t.text    :fallback_message
      t.text    :handoff_rule
      t.jsonb   :starter_questions, null: false, default: []
      t.string  :tone
      t.jsonb   :config, null: false, default: {} # model, temperature, business_hours, max_turns, guardrails…
      t.boolean :enabled, null: false, default: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :autonomia_agents, %i[account_id status]
    add_index :autonomia_agents, %i[account_id agent_type]
  end

  def create_sources
    create_table :autonomia_agent_sources do |t|
      t.references :autonomia_agent, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string  :source_type, null: false       # link|pdf|xlsx|docx|json|txt|md
      t.string  :reference                       # nome do arquivo OU url
      t.string  :external_link                   # url (quando link)
      t.integer :status, null: false, default: 0 # enum: pending:0, processing:1, ready:2, failed:3
      t.string  :sync_status                     # texto livre p/ progresso ("3/12 chunks")
      t.string  :sync_token                      # token-guard da ingestão (anti-supersede)
      t.text    :error
      t.jsonb   :metadata, null: false, default: {} # fingerprint, byte_size, chunk_count, mime…
      t.datetime :synced_at
      t.timestamps
    end
    add_index :autonomia_agent_sources, %i[autonomia_agent_id status]
  end

  def create_knowledge
    create_table :autonomia_agent_knowledge do |t|
      t.references :autonomia_agent, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.bigint  :source_id                       # FK lógico -> autonomia_agent_sources
      t.text    :content, null: false
      t.vector  :embedding, limit: 1536
      t.integer :status, null: false, default: 1 # enum: pending:0, ready:1
      t.integer :chunk_index, null: false, default: 0
      t.jsonb   :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :autonomia_agent_knowledge, %i[autonomia_agent_id status],
              name: 'idx_autonomia_knowledge_agent_status'
    add_index :autonomia_agent_knowledge, :source_id
    add_index :autonomia_agent_knowledge, :embedding, using: :ivfflat,
                                                       opclass: :vector_l2_ops, name: 'idx_autonomia_knowledge_embedding'
  end

  def create_build_threads
    create_table :autonomia_agent_build_threads do |t|
      t.references :autonomia_agent, null: true, foreign_key: true # null até o agente nascer
      t.references :account, null: false, foreign_key: true
      t.jsonb   :messages, null: false, default: [] # [{role, content, at}]
      t.jsonb   :state, null: false, default: {}    # draft_config parcial, needs_more_info, turn
      t.string  :build_token                        # token-guard da geração do construtor
      t.integer :status, null: false, default: 0    # enum: open:0, processing:1, ready:2, failed:3
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :autonomia_agent_build_threads, %i[account_id status]
  end
end
