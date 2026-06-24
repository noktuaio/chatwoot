# Progress — Módulo Agentes Autonom.ia (construção orquestrada A→F)

Plano de referência: `docs/autonomia_agents_plan.md`. Namespace `Autonomia::Agents::*`, tabelas
`autonomia_agent_*`. Build na árvore + testes em ambiente efêmero. Deploy só com OK do PO.

## Estado geral
| Fase | Escopo | Status |
|---|---|---|
| A — backend | fundação (embed+retriever) + conhecimento (ingestão) + Construtor IA + entidade Agente | ✅ verde (teste isolado all_pass) |
| B | conversar (RAG + portão de confiança) + Testar/Copiloto | ✅ verde (all_pass, 1ª tentativa, sem vazamento) |
| C | operar (bot nativo + debounce + multicanal + handoff) | ✅ verde (all_pass; zero-regressão + anti-loop provados) |
| D | plugar no Kanban (auto-estágio/handoff/follow-up — reúso) | ✅ verde (all_pass; não-regressão + bug de idempotência corrigido) |
| FE | wizard do Construtor + Painel (Testar/Conhecimento/Canais/Desempenho/Ajustar) + sidebar Agentes | ✅ verde (vite build OK, eslint 0 erros, 13/13 unit) |
| F | refino (analytics da aba Desempenho + logging por resposta + insights) | ✅ verde (all_pass backend + vite build OK) |

> Nota de sequência: backends B→C→D primeiro, depois UMA fase de FE consolidada (Construtor + Painel + nav),
> para a UI ser construída contra endpoints completos e evitar retrabalho em arquivos compartilhados (sidebar/router/store).

## Princípios (invioláveis)
- Sem regressão. Migrações aditivas. Codex review + teste isolado por fase. Backup antes de
  destrutivo. Whitelabel. Feature flag `AUTONOMIA_AGENTS_ENABLED`. Reaproveitar CRM/IA/pgvector.

## Log
- 2026-06-15: doc do plano aprovado; progress criado; iniciada Fase A (backend) via workflow.
- 2026-06-15: **Fase A backend ✅** — 35 arquivos (`autonomia_agent_*` + `Autonomia::Agents::*`), migração aditiva
  (pgvector vector(1536)+ivfflat), Construtor IA gera agente com instrução OCULTA, serializer não vaza IP.
  Review triplo (Codex+crítico+segurança) + teste isolado real `all_pass:true`. 3 bugs de boot/migração caçados
  e corrigidos (Gemfile sem bundle install na imagem → removidos pdf-reader/roo/rubyzip; índices duplicados; nomes
  Zeitwerk dos processors). Bug latente do rescue docx/xlsx (NameError mascarando UnsupportedFormat) corrigido à mão.
  Formatos ativos hoje: txt/md/json/link (pdf/xlsx/docx degradam grac. até gems numa imagem base futura). Prod intocada (email-22).
- 2026-06-15: iniciada **Fase B** (motor de resposta: RAG + portão de confiança + Testar) via workflow.
- 2026-06-15: **Fase B ✅** — PromptBuilder (instrução/scaffold OCULTOS + guardrails + bloco de contexto RAG),
  Answerer (Retriever→prompt→ResponsesClient#create estruturado→portão de confiança→decisão de handoff; erro/timeout
  do LLM → handoff seguro, nunca 500), Playground+Copilot + endpoint `POST .../agents/:id/test` (e `/suggest`),
  jbuilders que devolvem só { reply, confidence, handoff, used_knowledge }. Review triplo + teste isolado real
  `all_pass:true` (1ª tentativa, 0 correções): resposta confiante, portão de confiança, handoff explícito, erro de LLM,
  e NÃO-VAZAMENTO de instruction/scaffold/prompt no endpoint. Prod intocada.
- 2026-06-15: iniciada **Fase C** (operar: bind inbox + listener + debounce + resposta multicanal + handoff) via workflow,
  com ênfase em ZERO regressão no pipeline de mensagens (revisor de regressão dedicado + teste do caso "sem bind → sem efeito").
- 2026-06-15: **Fase C ✅** — vínculo `autonomia_agent_inboxes` (UNIQUE inbox, coexistência c/ Gabriela), `MessageListener`
  registrado no `AsyncDispatcher` espelhando o CRM (sem tocar dispatch core), `ReplyJob` (debounce 6s, token last-writer-wins),
  `Responder` (history + Answerer + post outgoing canônico canal-agnóstico, sender AgentBot), `HandoffHandler` (graceful + bot_handoff! →
  open/unassigned), `InboxConnector` + `ChannelsController`. Review quádruplo (Codex+crítico+segurança+REGRESSÃO) + teste isolado real
  `all_pass:true`: caso-0 sem-bind no-op, 1 resposta por rajada, handoff silencia o bot, anti-loop, multicanal (web + Channel::Api). Prod intocada.
- 2026-06-15: iniciada **Fase D** (plugar no Kanban: handoff real via HandoffExecutor + guarda da interação bot×auto-followup + card/timeline) via workflow.
- 2026-06-16: **Fase D ✅** — `Operate.active_for?` (gate canônico), `HandoffAssigner` + `Crm::Ai::HandoffMemberSelector` (refactor puro do
  HandoffExecutor, comportamento do Kanban idêntico), `HandoffHandler` chama assigner (membro/round-robin/team/none), guarda
  `native_agent_active?` ADITIVA no `AutoFollowupPlanner` (com flag OFF = byte-idêntico), card `autonomia_handoff` IP-safe. Review (Codex+
  crítico+REGRESSÃO) + teste isolado real `all_pass:true` (15 asserts). **Bug latente corrigido**: guards de idempotência usavam
  `content_attributes->>'key'` que nunca casava (JSON duplo-encodado) → trocado por regex `::text ~`, evitando handoff/resposta duplicada em retry.
  **Backends A–D completos e verdes na árvore. Prod ainda em email-22 (não deployado).**
- NOTA DE DEPLOY: `db/schema.rb` está defasado (não tem as tabelas autonomia, migrações 2026-06-16/17). Deploy DEVE usar `db:migrate`
  (não `db:schema:load`) — que é o gate padrão do fork. Sem impacto em prod; só registro.
- 2026-06-16: iniciada **fase FE consolidada** (sidebar Agentes + Construtor wizard + Painel Testar/Conhecimento/Canais/Ajustar/Desempenho) via workflow.
- 2026-06-16: **FE ✅** — sidebar "Agentes" (flag FE `AUTONOMIA_AGENTS_ENABLED` no globalConfig + beforeEnter), rotas aditivas, store
  (4 módulos via factory) + 4 API clients, Hub (AgentCard/AgentTypePicker), Construtor (BuilderChat/ReviewCard/KnowledgeDrop),
  Painel (Test/Knowledge/Channels/Tune/Performance + SourceAddDialog), i18n `agents.json`. Review triplo (Codex+crítico+Vue/UX).
  Gate: `vite build --mode production` OK (chunks emitidos), eslint 0 erros (9 warns i18n-dynamic-key, padrão do codebase), 13/13 vitest.
  IP oculto (instruction só em PanelTune modo manual), whitelabel ok, navegação intacta. Bugs caçados: AgentsHubPage.vue faltando, payload do upload.
- 2026-06-16: iniciada **Fase F** (refino: analytics reais da aba Desempenho + logging leve por resposta + insights de lacuna) via workflow.
- 2026-06-16: **Fase F ✅** — `autonomia_agent_events` (aditiva), `EventLogger` best-effort (rescue → nunca quebra resposta/handoff),
  logging no Responder (replied) e HandoffHandler (handed_off) só no caminho autonomia, `Analytics` (rates sem div/0, group por NOME do enum,
  timeline, insight de lacuna, escopo por conta), endpoint `GET .../agents/:id/analytics?range=7d|30d` + jbuilder IP-safe, `PanelPerformance.vue`
  ligado (cards/timeline/top-reasons/insight/range/loading-empty-erro). Review (Codex+crítico+REGRESSÃO) + gate duplo: backend `all_pass:true`
  (eventos, agregação, div-por-zero, escopo, best-effort) + `vite build` EXIT 0.

- 2026-06-16: **Gate por conta (pré-deploy)** — PO escolheu deploy + ativar só na conta de teste (conta 12, inbox 149 p/ live).
  1ª tentativa usou o sistema de features do Chatwoot (features.yml) → `autonomia_agents` virou a 64ª feature → bit 64 (2^63) ESTOURA o
  signed bigint `accounts.feature_flags` (quebraria TODA criação de conta!). O agente "consertou" reescrevendo o concern central `featurable.rb`
  + coluna `feature_flags_2`. REJEITADO por raio de regressão (concern de todas as features). **Correção:** restaurar featurable.rb/features.yml ao
  original (da imagem base), remover a migração feature_flags_2, e usar um **gate ISOLADO por conta** (jsonb interno de accounts OU tabela própria
  `autonomia_enabled_accounts`) + `Config.enable_for!/disable_for!` + campo aditivo `autonomia_agents_enabled` no payload da conta p/ o FE.
  Em construção via workflow (revert+reimpl → Codex → teste isolado). Inbox 149 = WhatsApp WAHA real → conexão ao vivo SÓ com OK do PO no momento.
- 2026-06-16: **Gate isolado ✅** — featurable.rb/features.yml restaurados BYTE-IDÊNTICOS ao base image (md5 d9094261.../8369f3d8...),
  migração feature_flags_2 deletada, gate vive em `accounts.internal_attributes['autonomia_agents_enabled']` (sem migração/coluna/tabela nova,
  zero toque no feature system). `Config.enable_for!/disable_for!(account)` + campo aditivo `autonomia_agents_enabled` no _account.json.jbuilder;
  Sidebar/router gateiam por ele + master ENV. Teste isolado `all_pass` (Account.create ok sem overflow, feature existente resolve, gate on/off por
  conta, kill-switch, payload). **BD prod (read-only, autorizado):** inbox 149 = conta 12 "Enterprise", Channel::Api, nome "Teste CAixa de entrada"
  (inbox de TESTE), SEM agent_bot vinculado → conector aceita. Deploy liberado pelo PO (deploy + ativar só na conta 12).
- 2026-06-16: **DEPLOY CONCLUÍDO ✅** — imagem `chatwoot-campaign-import:v4.14.1-20260616-autonomia1` no ar (app+sidekiq, start-first, rc=0,
  /health 200, sem downtime). Backup validado: `/root/backups/autonomia_predeploy_20260616.dump` (pg_restore -l ok, 118 tabelas).
  Gates: eager_load PASS, migração das 3 tabelas autonomia aplicada limpa (status confirmado: só elas pendentes), smoke 200.
  Master ENV `AUTONOMIA_AGENTS_ENABLED=true` adicionado a app+sidekiq. **Feature ATIVA SÓ na conta 12** (verificado no Rails prod:
  Config.enabled?(acc12)=true, outra conta=false). Recurso inerte até agora (nenhum inbox conectado).
  PENDENTE: validação visual (Playwright precisa de identidade de usuário da conta 12 — bloqueado ler PII; aguardando decisão do PO) +
  conexão do inbox 149 (só com OK explícito do PO). Rollback: redeploy da tag email-22 + (se preciso) restore do dump.
- 2026-06-16: **Validação visual do PO (conta 12) achou 3 problemas REAIS:** (1) i18n — só EN, falta pt_BR (DEFAULT_LOCALE=pt_BR) → tudo em inglês;
  (2) Construtor não responde — CONFIRMADO bug de FE: backend gera BuildThread `ready` com `needs_more_info=true`+`next_question` (em PT, correto!),
  mas o FE trata "ready" como "agente pronto" e busca agente inexistente → não renderiza a next_question (loop de entrevista quebrado). Backend OK,
  porém lento (~25s, modo background+reasoning high). (3) UI/UX crua, precisa passe de design mantendo identidade Chatwoot.
  → Workflow de correção em curso: turn-loop FE + builder síncrono (reasoning low/med) + pt_BR/pt/es agents.json + UX polish + review Vue/UX + vite build.
  Depois: rebuild imagem autonomia2 + redeploy. Lição: backend recebeu rigor extremo; FE/UX/i18n ficaram aquém na 1ª passada.

## ✅ MÓDULO COMPLETO (A–F) — verde na ÁRVORE, NÃO deployado (prod = email-22)
Estado integrado validado junto no gate da Fase F (docker build do tree + db:migrate de TODAS as migrações + boot; e vite build do app inteiro).
Migrações autonomia: 20260616120000 (A), 20260617120000 (C), 20260618120000 (F) — aplicam em sequência limpa.
PENDÊNCIAS p/ deploy (todas conhecidas, nenhuma bloqueia o build):
- `db/schema.rb` defasado → deploy DEVE usar `db:migrate` (gate padrão do fork), nunca `db:schema:load`.
- Formatos de conhecimento ativos: txt/md/json/link. pdf/xlsx/docx degradam graciosamente (faltam gems pdf-reader/roo/rubyzip na imagem base
  — exigiria imagem base com bundle install; decisão futura).
- Flag `AUTONOMIA_AGENTS_ENABLED` (backend + FE globalConfig) — ligar só quando for ativar.
- Deploy = build vite + docker build + backup pg_dump + gate eager_load + migração via serviço temp + start-first + smoke + Playwright real. SÓ com OK do PO.
