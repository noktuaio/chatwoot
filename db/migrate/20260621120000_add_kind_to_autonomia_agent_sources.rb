class AddKindToAutonomiaAgentSources < ActiveRecord::Migration[7.0]
  # ADITIVA (só add_column + add_index) → eager_load + db:migrate sem downtime; fontes antigas
  # assumem o default `knowledge:0` (caminho atual inalterado — ZERO regressão).
  #
  # `kind` separa os DOIS grupos de materiais (decisão do PO §1 do plano v2):
  #   - knowledge (0): "o que ela SABE". Caminho atual: ingest → chunk → embed → revisora.
  #   - media (1):     "o que ela ENVIA" (catálogo, tabela, imagem). NÃO embeda, NÃO passa pela
  #                    revisora de qualidade de KB; é só armazenada (status ready direto).
  #
  # Índice composto (autonomia_agent_id, kind): a 2ª aba ("O que ela pode enviar") e o contexto do
  # Construtor (mídias de envio) filtram sempre por agente + kind.
  def change
    add_column :autonomia_agent_sources, :kind, :integer, null: false, default: 0
    add_index  :autonomia_agent_sources, %i[autonomia_agent_id kind]
  end
end
