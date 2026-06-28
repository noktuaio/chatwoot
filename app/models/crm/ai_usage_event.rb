class Crm::AiUsageEvent < ApplicationRecord
  self.table_name = 'crm_ai_usage_events'

  # Append-only telemetria de consumo de IA. NUNCA guarda prompt/instrução/resposta —
  # só metadados de uso (feature, modelo, tokens, custo, latência) p/ o dashboard Gestão IA.
  belongs_to :account

  validates :feature, presence: true
  validates :model, presence: true

  scope :since, ->(time) { where('created_at >= ?', time) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }

  # Agrega gasto por feature numa janela: { feature => { calls:, cost:, ...tokens } }.
  # Usado pelo dashboard (Fase 3.2). Modelo só é exposto na camada de view p/ super-admin.
  def self.spend_by_feature(scope = all)
    scope.group(:feature).pluck(
      :feature,
      Arel.sql('COUNT(*)'),
      Arel.sql('COALESCE(SUM(cost_estimate), 0)'),
      Arel.sql('COALESCE(SUM(input_tokens), 0)'),
      Arel.sql('COALESCE(SUM(cached_tokens), 0)'),
      Arel.sql('COALESCE(SUM(output_tokens), 0)')
    ).to_h do |feature, calls, cost, input, cached, output|
      [feature, { calls: calls, cost: cost, input_tokens: input, cached_tokens: cached, output_tokens: output }]
    end
  end
end
