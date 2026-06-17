class AddReviewFieldsToAutonomiaAgentSources < ActiveRecord::Migration[7.0]
  # Aditiva (só add_column) → eager_load + db:migrate sem downtime; campos ficam nil em sources
  # antigas (compat). Guardam o parecer da IA Revisora por fonte. O topic_map / confiança geral
  # da base ficam no jsonb `autonomia_agents.config` (sem migração).
  def change
    add_column :autonomia_agent_sources, :quality_score,  :integer  # 0..100, nil até revisar
    add_column :autonomia_agent_sources, :confidence,     :string   # 'alta'|'media'|'baixa'
    add_column :autonomia_agent_sources, :review_status,  :string   # 'accepted'|'needs_resend'|'needs_review'|nil
    add_column :autonomia_agent_sources, :review_summary, :text      # resumo 1–3 frases (só se aceito)
    add_column :autonomia_agent_sources, :review_label,   :string   # 'otima'|'boa'|'fraca'
    add_column :autonomia_agent_sources, :review_reason,  :text      # motivo curto, pt-BR
    add_column :autonomia_agent_sources, :reviewed_at,    :datetime
  end
end
