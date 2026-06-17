module Autonomia
  module Agents
    # Fase F — evento ADITIVO de operação (replied/handed_off). Imutável (só created_at).
    # Guarda apenas métricas seguras: confidence, answered_from_knowledge e um motivo de
    # handoff CURADO/truncado pelo EventLogger. NUNCA contém instruction/scaffold/prompt.
    class AgentEvent < ApplicationRecord
      self.table_name = 'autonomia_agent_events'

      belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id
      belongs_to :account

      enum event_type: { replied: 0, handed_off: 1 }

      scope :in_range, ->(from, to) { where(created_at: from..to) }
    end
  end
end
