json.id agent.id
json.name agent.name
json.avatar_url agent.avatar_url
json.agent_type agent.agent_type
json.status agent.status
json.mode agent.mode
json.human_card agent.human_card
json.greeting agent.greeting
json.fallback_message agent.fallback_message
json.handoff_rule agent.handoff_rule
json.starter_questions agent.starter_questions
json.tone agent.tone
json.config agent.config
# Revisor v2: MAPA DE TEMAS + confiança geral + resumo da base (UI de Conhecimento). Seguros de
# expor (vêm do jsonb `config`, NUNCA de instruction/scaffold). Já estão dentro de `config`; expô-los
# no topo dá chaves estáveis ao FE.
json.topic_map Array(agent.topic_map)
json.knowledge_confidence agent.knowledge_confidence
json.knowledge_summary agent.knowledge_summary
json.enabled agent.enabled
# IP oculto: `scaffold` JAMAIS é exposto. `instruction` só aparece em modo manual (texto do
# próprio usuário, visível); em modo guiado a instrução é gerada pelo Construtor e permanece oculta.
json.instruction agent.instruction if agent.manual?
# #3 INSTRUÇÃO VIVA (C): booleano SEGURO (NUNCA o texto) para o FE saber se um agente guiado já tem
# instrução (foi finalizado). Usado pelo PanelTest para avisar que um rascunho não-finalizado ainda
# não reflete o comportamento real. IP OCULTO preservado: expõe presença, não conteúdo.
json.has_instruction agent.instruction.present?
json.created_at agent.created_at
json.updated_at agent.updated_at
