module Autonomia
  module Agents
    class KnowledgeEntry < ApplicationRecord
      self.table_name = 'autonomia_agent_knowledge'

      has_neighbors :embedding, normalize: true # gem neighbor (cosine via normalize)

      belongs_to :account
      belongs_to :agent, class_name: 'Autonomia::Agents::Agent',
                         foreign_key: :autonomia_agent_id
      belongs_to :source, class_name: 'Autonomia::Agents::Source',
                          foreign_key: :source_id, optional: true

      enum status: { pending: 0, ready: 1 }
    end
  end
end
