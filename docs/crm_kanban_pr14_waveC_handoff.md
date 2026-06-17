# CRM Kanban PR14 — Onda C HANDOFF (auto-contido p/ pós-compactação)

> Leia este doc + `docs/crm_kanban_pr14_plan.md` (plano completo das 8 frentes) + `/root/docker-stacks/progress.md` (Phases 35–37.2). Este arquivo tem TUDO para executar a Onda C sem contexto prévio.

## 0. Estado atual (2026-06-09)

- **Repo:** `/root/docker-stacks/build/chatwoot-campaign-v4.14.1` (fork Chatwoot v4.14.1, edition `ee`).
- **ONDA C COMPLETA — PR14 INTEIRO CONCLUÍDO.** Em produção (web + Sidekiq Swarm): `chatwoot-campaign-import:v4.14.1-20260609-crm14d`. Host: `https://chat.autonomia.site`. Conta de teste: **6** (pipeline 9 "Seguro Viagem", inbox 113 WhatsApp, AgentBot "Agente Gabriela").
- **Flags (env nos 2 serviços):** `CRM_KANBAN_ENABLED=true`, `CRM_AI_ENABLED=true`, `CRM_AI_MEDIA_ENABLED` não setado (= default `true`).
- **Rollback seguro:** `crm14d → crm14c → crm13.3`. Backup pré-PR14: `backups/crm_pr14_predeploy_20260609T121102Z`.
- **PR14.8 (crm14c):** migrations `closed_at` + 2 índices concurrent; dashboard sob CRM; fechar negócio no drawer; autofill de valor pela IA. **PR14.9 (crm14d):** handoff IA→humano (atribuição + bot_handoff! + loop guard; config por etapa). Ambas deployadas e verificadas. Este doc agora é histórico/referência.
- **Onda A (DONE, deployada, testada):** PR14.1 permissões CRM granulares (custom roles), PR14.2 hardening payload/realtime, PR14.7a filtro Status removido do board + filtro `result` na Lista.
- **Onda B (DONE, deployada, testada visualmente):** PR14.3 UI dos cards, PR14.4 timeline humanizada, PR14.5 resumo IA no drawer, PR14.6/selo→chip de estágio na lista de conversas, PR14.7b/c filtros.
- **Onda C (PENDENTE — este handoff):** PR14.8 dashboard de relatórios; PR14.9 handoff inteligente IA→humano.

## 1. WORKFLOW de build → verificação → deploy (OBRIGATÓRIO, nesta ordem)

Use orquestração dinâmica (Workflow tool) para implementar+review por sub-PR; mas build/deploy/migration são feitos no main loop. Gates aprendidos na marra:

1. **Implementar** (sequencial p/ evitar colisão de arquivos; review independente por sub-PR).
2. **Lint/syntax:** `ruby -c <file>` em todo .rb; `node_modules/.bin/eslint --fix <file>` em .vue/.js. `node -e JSON.parse` nos locales.
3. **i18n:** adicionar chaves em `app/javascript/dashboard/i18n/locale/en/*.json` **E** `pt_BR/*.json` (instalação pt-BR; backend en.yml + pt_BR.yml).
4. **Vite build** (se mudou frontend): `rm -rf public/vite && NODE_OPTIONS="--max-old-space-size=6144" RAILS_ENV=production NODE_ENV=production node_modules/.bin/vite build --mode production` (~3min).
5. **Docker build:** `DOCKER_BUILDKIT=1 docker build -f docker/custom/Dockerfile.crm -t chatwoot-campaign-import:v4.14.1-20260609-crm14c .` (Dockerfile só faz `FROM chatwoot/chatwoot:v4.14.1` + COPY; reusa public/vite do host). pnpm NÃO está no PATH; use `node_modules/.bin/vite`.
6. **GATE eager_load (OBRIGATÓRIO se mexeu em .rb — produção roda `eager_load=true`):** rode num **serviço Swarm temporário** na `network_public` (não dá `docker run` nela — não é attachable):
   ```
   docker service inspect chat-autonomia_chatwoot_app --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' > /tmp/env.list
   mapfile -t E < /tmp/env.list; A=(); for l in "${E[@]}"; do [ -n "$l" ] && A+=(--env "$l"); done
   docker service create --name eager_test --network network_public --restart-condition none --detach "${A[@]}" \
     --entrypoint sh <TAG> -c 'cd /app && bundle exec rails runner "Rails.application.eager_load!; puts \"EAGER_OK\""'
   # esperar Complete, ver logs por EAGER_OK, depois: docker service rm eager_test
   ```
7. **Green-check:** agente review independente (Agent tool) verifica diff + must-fix + 0 regressão (diff arquivos core byte-a-byte vs imagem anterior). GO/NO_GO.
8. **Deploy (gated em GO + autorização do usuário):**
   ```
   docker service update --image <TAG> --no-resolve-image --update-order start-first chat-autonomia_chatwoot_app
   docker service update --image <TAG> --no-resolve-image chat-autonomia_chatwoot_sidekiq
   ```
   (Flag é `--no-resolve-image`, NÃO `--resolve-image never`. Single-node Swarm, imagens locais.)
9. **Migration (se houver — só a 14.8 tem):** rode via `docker exec <web_cid> bundle exec rails db:migrate` no container novo (start-first mantém o velho até convergir). Índices `CONCURRENTLY` precisam `disable_ddl_transaction!`.
10. **Smoke real + TESTE VISUAL (OBRIGATÓRIO p/ UI):** `curl` 200 NÃO basta. Para UI, logar via SSO + Playwright e inspecionar DOM/screenshot:
    - SSO (autorizado pelo usuário): `u=Account.find(6).administrators.first; tok=u.generate_sso_auth_token; URL="https://chat.autonomia.site/app/login?email=#{CGI.escape(u.email)}&sso_auth_token=#{tok}"` (token expira rápido; gere e use na hora).
    - Playwright MCP: `npx playwright install chrome` (1x). `browser_resize` largo (1600x900) p/ layout expandido. `browser_navigate` SSO URL → app URL. `browser_evaluate` p/ checar DOM (`[data-...]`, contagens). `browser_network_requests`/`browser_network_request` p/ ver request/response real.
11. **Atualizar `progress.md`** ao fim de cada onda/fase.
12. **Agentes de teste por frente** (pós-deploy) aprovam/reprovam com asserts reais (não 200-ok). Para UI, complementar com o teste visual Playwright acima.

## 2. GOTCHAS desta base (TODOS já causaram bug nesta sessão — não repetir)

1. **`display_id` ≠ id global:** o frontend Chatwoot identifica conversa por **`display_id`** (por conta). Endpoints que recebem id de conversa do front DEVEM casar por `display_id` (`Current.account.conversations.find_by!(display_id: ...)`), e respostas em lote por conversa devem ser **keyed por display_id**. (Quebrou o selo de estágio e o badge sidebar.)
2. **Zeitwerk + `eager_load=true`:** `config.eager_load_paths += Dir["enterprise/app/**"]` torna cada subdir de `enterprise/app/*` um **root** de autoload. NÃO ponha arquivo autoloadável em `enterprise/app/<x>/concerns/` (Zeitwerk espera `Concerns::Nome`, não colapsa). Coloque módulos EE em `enterprise/app/policies/enterprise/crm/<nome>.rb` como `Enterprise::Crm::<Nome>` (padrão das policies). **Sempre rode o gate eager_load antes de deploy** (um deploy caiu por isso → outage → rollback).
3. **`Message` tem `default_scope { order(created_at: :asc) }`:** use `.reorder(id: :desc)` (não `.order`) para pegar as mensagens recentes. Ver `Crm::Ai::ContextBuilder`.
4. **`ApplicationRecord#validates_column_content_length`** limita QUALQUER coluna string a 255 chars a menos que exista um `validates :col, length:` explícito (mesmo a coluna sendo varchar(500)). Ver `Crm::AiStageSuggestion#reasoning` (tem `length: {maximum: 500}`).
5. **Card kanban (flexbox):** card com `overflow-hidden` dentro de coluna `flex-col` precisa `shrink-0`, senão colapsa quando a coluna enche (`overflow:hidden` zera o `min-height:auto`).
6. **Permissões (decisão travada):** "se o admin deu, o cara tem". Admins E agentes sem custom_role mantêm acesso TOTAL ao CRM (`Enterprise::Crm::*Policy` via concern `enterprise/app/policies/crm_permissions.rb` → `CrmPermissions`, com `prepend_mod_with` nas 9 policies OSS). Backfill `crm:backfill_role_permissions` concede baseline aos custom roles existentes (rodar no cutover). Keys já existem: `crm_view, crm_manage_cards, crm_move_cards, crm_manage_pipelines, crm_manage_ai, crm_view_reports, crm_admin`.
7. **Builders de payload são compartilhados** (`Crm::Cards::PayloadBuilder`, `Crm::Kanban::CardPayloadBuilder`, `Crm::Cards::SharedFilters`); board manda timestamps em **epoch segundos**, broadcaster manda ISO — o front tolera os dois (timeHelper fromUnixTime + helpers que aceitam ambos). Não quebre isso.

## 3. ONDA C — escopo, decisões travadas e must-fix

### PR14.8 — Dashboard de relatórios do CRM (em Relatórios) [L, ~26-36h]
- **Migration (ÚNICA do PR14):** adicionar `crm_cards.closed_at` (datetime) + callback `before_save` que seta `closed_at` quando status→won/lost e limpa ao reabrir. **Sem isso, KPIs won/lost/cycle-time por período saem errados (não usar `updated_at`).** Backfill `closed_at = updated_at` p/ cards já won/lost (one-time, idempotente). Índices `CONCURRENTLY`: `crm_ai_stage_suggestions [account_id,status,created_at]` e `crm_cards [account_id,pipeline_id,status,closed_at]`.
- **Ação de fechar negócio no card (DECISÃO TRAVADA do usuário):** o card JÁ tem `enum status {open,won,lost,archived}`, `value_cents`+`currency`, `lost_reason`. Adicionar no TOPO do `CrmCardDrawer` um bloco de status com **Ganhar / Perder / Reabrir**. "Ganhar" abre diálogo que confirma o **valor** (pré-preenchido pela IA, ver abaixo); "Perder" pede `lost_reason`; "Reabrir" volta a `open` (callback limpa `closed_at`). Gate `crm_manage_cards`. Auditar via `Crm::ActivityLogger` (`won`/`lost`/`reopen`) e renderizar humanizado na timeline 14.4 (`describeActivity` cobre esses tipos). Win/lost do relatório = essa decisão explícita, NÃO inferência de "chegou na última etapa".
- **Valor extraído da conversa via IA (DECISÃO TRAVADA: AUTOPREENCHE SEMPRE, humano corrige):** schema ÚNICO do `Crm::Ai::StageClassifier` estendido com `value{ amount_cents, currency }` nullable (mesma chamada LLM do classify/handoff). `Crm::Ai::Evaluator#apply_ai_value!` grava `card.value_cents`/`currency` **direto** quando a IA detecta valor. ÚNICA trava: takeover humano — quando alguém edita o valor (controller `update` com `value_cents`, ou Ganhar com valor → `metadata.ai.value_source='human'`), a IA NÃO reescreve mais. `metadata.ai.value_source` ('ai'/'human') + `value_filled_at` expostos via `PayloadBuilder#ai_value_payload` (gated por visibilidade) p/ a UI badgear "preenchido pela IA". Reusa a leitura multimodal existente.
- **Funil vs Pipeline (terminologia):** mesmo conceito; código/inglês = `pipeline`, tela pt_BR = **"Funil"**. Uma conta tem vários funis; uma inbox pode estar ligada a >1 funil (`crm_pipeline_inboxes` N:N); cada card vive em 1 funil. Por isso o dashboard mostra **um funil por vez** (seletor obrigatório, default `is_default`) — não dá pra empilhar etapas/valores de funis diferentes.
- **Authz:** o controller de relatórios DEVE ter `before_action { authorize :report, :view? }` (o `Crm::BaseController` só força a flag CRM, NÃO Pundit). Gate de UI por `crm_view_reports` (key já existe).
- **Métricas:** funil por etapa (single-pipeline, com seletor obrigatório, default pipeline `is_default`); win/lost (via `closed_at`); valor por etapa **agrupado por moeda** (não somar moedas diferentes); tempo em etapa (`entered_stage_at`); IA auto-move vs humano via **`crm_ai_stage_suggestions.status`** (NÃO reconstruir de JSON de move); sugestões aceitas/dispensadas; workload por responsável (incl. bot vs humano); follow-ups due/overdue; throughput no tempo; por canal/source.
- **Front:** reusar componentes de relatório do Chatwoot (`dashboard/routes/dashboard/reports/`), identidade visual Chatwoot. Builders `Crm::Reports::*`. Pode ser 2 PRs empilhados (backend+índices, depois front).
- **DECISÃO TRAVADA (etapa x ganho):** win/lost é **independente do estágio**. O card pode estar em qualquer etapa e ser marcado won/lost. Funil = estágios; win/lost = `status`. NÃO acoplar "mover para última etapa" a fechamento (padrão Pipedrive/HubSpot). A fundação (`sync_closed_at`) já assume isso.

### PR14.9 — Handoff inteligente IA→humano (Editar funil) [XL, ~32-44h; 9a backend / 9b UI]
- **Decisão travada do usuário:** "handoff É atribuição. Quando entrar online, atribui." → handoff = atribuir a conversa a um humano usando o mecanismo do Chatwoot; sem mensagem ao cliente (manter simples); status via `bot_handoff!`.
- **MUST-FIX (blockers confirmados em review):**
  1. **Parar o bot:** atribuir humano NÃO desliga o AgentBot da inbox → cliente recebe humano + bot juntos. DEVE chamar `conversation.bot_handoff!` (transiciona pending→open, tira do bot).
  2. **Guard de loop/idempotência ANTES da chamada LLM/atribuição:** `assignee.changed` re-enfileira avaliação (via `Crm::ConversationObserverListener#assignee_changed` → `SyncConversationCardJob`); sem guard, loop.
- **Design:** config de handoff em `pipeline/stage.metadata` (instrução/gatilho por etapa, igual `ai_criteria`); modo **direto** (nome citado pela IA que bate com membro da inbox → atribui a ele) ou **round-robin** entre membros da inbox (preferir online; se ninguém online, atribui mesmo assim — "pega quando entrar online"). Estender o schema ÚNICO do `Crm::Ai::StageClassifier` com um campo `handoff{}` (sem segunda chamada LLM). Validar só membros da inbox. Auditar como atividade `ai_handoff` (e renderizar humanizado na timeline — coordenar com a lógica de `describeActivity` do PR14.4; cobrir `ai_handoff`). Atrás da flag `CRM_AI_ENABLED`. Gate de config por `crm_manage_ai`.
- Sequência: 9a (backend) depois 9b (UI no `CrmAiSettingsPanel`/`CrmPipelineDrawer` + plumbing de membros da inbox + i18n + render timeline `ai_handoff`). 14.4 (timeline) já está no ar, então `ai_handoff` deve entrar no mapa de `describeActivity`.

#### Exemplos REAIS (referência de implementação)

**(a) Config por etapa em `stage.metadata.ai_handoff`** (setada no drawer "Editar funil", igual `ai_criteria`):
```json
{ "ai_handoff": { "enabled": true, "mode": "round_robin",
  "trigger": "Quando o cliente pedir para falar com uma pessoa ou demonstrar intenção clara de compra.",
  "prefer_online": true } }
```
`mode: "direct"` = atribui ao agente citado pela IA (se ⊂ membros da caixa); `"round_robin"` = rodízio entre membros (prefere online; se ninguém online, atribui mesmo assim).

**(b) Schema ÚNICO do `StageClassifier` — `handoff{}` entra no MESMO JSON do classify+value** (sem 2ª chamada LLM):
```json
"handoff": { "type": ["object","null"],
  "properties": {
    "should_handoff": { "type": "boolean" },
    "reason": { "type": "string", "maxLength": 300 },
    "suggested_agent": { "type": ["string","null"] } },
  "required": ["should_handoff","reason","suggested_agent"], "additionalProperties": false }
```
Saída real do LLM:
```json
{ "suggested_stage_id": 42, "confidence": 0.82,
  "reasoning": "Cliente confirmou interesse e pediu para fechar.",
  "value": { "amount_cents": 150000, "currency": "BRL" },
  "handoff": { "should_handoff": true,
    "reason": "Cliente pediu explicitamente um atendente humano.",
    "suggested_agent": "Gabriela" } }
```

**(c) Fluxo no `Evaluator` (guard ANTES de atribuir):**
```
1. classify → handoff.should_handoff == true
2. GUARD idempotência (antes de qualquer atribuição):
     • houve ai_handoff nas últimas 24h?  → pula
     • conversa já atribuída a humano?      → pula
3. stage.metadata.ai_handoff.enabled?       → senão ignora
4. escolhe agente: direct(match nome ⊂ membros) | round_robin(prefere online)
5. conversation.assignee = agente
6. conversation.bot_handoff!   ← desliga o AgentBot (pending→open)  [MUST-FIX]
7. ActivityLogger event_type: 'ai_handoff', payload {to_agent_id, reason, mode}
```
Sem o passo 2, `assignee.changed` re-enfileira `SyncConversationCardJob` → loop.

**(d) Timeline (`ACTIVITY_META.ai_handoff = { icon:'i-lucide-user-round-check', tone:'info' }`):**
```
🟦  Atribuído a humano pela IA                    há 2 min
    Agente Gabriela  →  Diego Sena
    "Cliente pediu para falar com um atendente."
```

**(e) MOCK da config de handoff (drawer "Editar funil", por etapa):**
```
┌ Etapa: Negociação ───────────────────────────────────────┐
│ Critérios de IA   [ textarea ... ]                        │
│                                                           │
│ ⚡ Passar para humano (handoff)              [ ●━ on ]    │
│   Quando atribuir a um atendente:                         │
│   [ Quando o cliente pedir falar com uma pessoa... ]      │
│   Modo:  ( ) Direto — IA escolhe pelo nome citado         │
│          (•) Rodízio entre os agentes da caixa            │
│          [✓] Preferir quem está online                    │
│   Agentes elegíveis (caixa "WhatsApp"): Gabriela, Diego…  │
└───────────────────────────────────────────────────────────┘
```

## 4. Componentes-chave já existentes (reusar, não recriar)
- IA: `app/services/crm/ai/` (config.rb thresholds 0.75/0.55, cap 12, MODEL_CLASSIFY=gpt-5.4-mini, MODEL_AUTO_MOVE=gpt-5.4, MODEL_SUMMARY=gpt-5.4-mini; evaluator.rb, stage_classifier.rb, context_builder.rb, responses_client.rb, conversation_summarizer.rb, media_enricher.rb, credential_resolver.rb).
- Permissões: `enterprise/app/policies/crm_permissions.rb` + `enterprise/app/policies/enterprise/crm/*_policy.rb`; front `useCrmPermissions` (`canViewReports`, `canManageAi` já existem).
- Timeline humanizada: `describeActivity` em `CrmCardDrawer.vue` + `ActivityPayloadBuilder` (backend labels). Adicionar `ai_handoff` aqui.
- Atividade/audit: `Crm::ActivityLogger`.
- Atribuição Chatwoot: `Conversation#assignee`, `AutoAssignment::AssignmentService`, `inbox.members`, `inbox.agent_bot_inbox`, `conversation.bot_handoff!`.
