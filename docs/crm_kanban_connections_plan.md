# Plano de Implementação — CRM "Conexões" (n8n / Webhooks / Tokens)

> Documento de arquitetura consolidado para o PR de Conexões do CRM Kanban (fork Chatwoot v4.14.1 EE, imagem `crm14f`).
> Sintetiza os 4 designs (Webhooks de saída, Tokens de API, API de entrada, Camada n8n) e dobra **todos os blockers** dos reviews independentes.
> Princípios não-negociáveis: **reuso da infra nativa do Chatwoot**, **aditivo e atrás de flags**, **zero regressão ao core (CE e EE)**, **segurança primeiro**.

---

## 1. Resumo executivo

### O que é
O CRM Kanban já existe (cards, pipelines/stages, IA de classificação/auto-move/handoff/valor, dashboard). Este PR abre o CRM para sistemas externos — principalmente **n8n** — em duas direções:

- **TRIGGER (CRM → n8n):** eventos de ciclo de vida do card (criado/movido/ganho/perdido/reaberto/arquivado, eventos de IA, follow-up) são emitidos como **webhooks de saída assinados (HMAC)** para URLs configuráveis por conta, reusando o `Webhook` nativo + `WebhookListener` + `WebhookJob`/`Webhooks::Trigger`.
- **ACTION (n8n → CRM):** sistemas externos chamam a **API REST de CRM existente** (`/api/v1/accounts/{id}/crm/*`) autenticados por **token de API revogável e escopado**, com **idempotência** (upsert por `external_id` + header `Idempotency-Key`).
- **Descoberta:** um **connection card "n8n"** em Settings → Integrações (espelhando `crm_kanban_ai`) que orienta o admin a mintar o token e configurar o webhook.

### Valor de negócio
Hoje o CRM é uma ilha: os eventos só vão para WebSocket (`Crm::Cards::Broadcaster` → `ActionCableBroadcastJob`), nunca para webhooks. Externamente, só é possível chamar a API com um token de usuário de sessão (escopo total, sem least-privilege, sem idempotência). Este PR transforma o CRM em um sistema **automável**: n8n pode reagir a "card ganho" para disparar faturamento, criar card a partir de um lead de formulário, mover cards conforme respostas, etc. — sem polling, com dedup e sem vazar PII.

### Exemplos de uso n8n
1. **Card ganho → cobrança:** trigger `crm.card.won` → nó Webhook do n8n → cria fatura no ERP.
2. **Lead externo → card:** formulário/Typeform → nó HTTP Request → `POST /crm/cards` com `external_id` (upsert idempotente, sem duplicar em retry).
3. **Resposta do cliente → mover stage:** webhook de mensagem → n8n → `POST /crm/cards/{id}/move`.
4. **Handoff de IA → alerta:** `crm.ai.handoff` → n8n → notifica time no Slack.

---

## 2. Decisões de produto a TRAVAR antes de implementar

> **STATUS (travado pelo usuário 2026-06-09):** D1 = token **por-conta escopado** ✅ · D5 = **adicionar retry limitado** aos webhooks de conta ✅ · Arranque = **Onda 1 primeiro, incremental** (deploy por onda, gates + OK do usuário). D2/D3/D4/D6–D10 seguem as recomendações abaixo (default).

> Cada decisão abaixo é **bloqueante de design**. Sem fechar, a implementação derrapa.

| # | Decisão | Recomendação travada | Por quê |
|---|---------|----------------------|---------|
| **D1** | **Princípio do token: por-conta (integração) vs por-usuário** | **Por-conta, escopado (estilo HubSpot Private App)**. NÃO usar token de usuário como caminho recomendado. | Token de usuário é credencial de **toda a API** (conversas, contatos com PII, relatórios), não apenas CRM — não há mecanismo nativo para escopá-lo só ao CRM. Confirmado no review da API de entrada: "User AccessToken is a full-API credential, not CRM-scoped." |
| **D2** | **Upsert por `external_id`** | **Sim, único por `(account_id, external_id)`** (espelha `contacts.identifier` / `uniq_identifier_per_account_contact`). Atômico via `create_or_find_by!` + retry em `RecordNotUnique`. | Retries do n8n são at-least-once; sem isso, cada retry cria card duplicado. |
| **D3** | **Quais eventos no MVP** | **MVP:** `crm.card.created`, `crm.card.moved`, `crm.card.won`, `crm.card.lost`, `crm.card.reopened`, `crm.card.archived`. **Fase 2:** `crm.card.updated`, `crm.card.value_changed`, `crm.ai.*`, `crm.follow_up.*`. | `card.updated`/`value_changed` não têm fonte de evento hoje (ver blocker B3 abaixo) e `card.updated` é ruidoso. IA é gated em `CRM_AI_ENABLED`. |
| **D4** | **Posição de PII no payload de saída** | **Excluir email/telefone/IA por padrão (default-deny)**, opt-in por webhook via flag `include_contact_pii`. | `Crm::Cards::PayloadBuilder` vaza email/phone/`ai_summary` hoje; emit é account-scoped sem `Current.user`. |
| **D5** | **Política de retry de webhook account** | **Adicionar `retry_on` limitado (timeout/connection/5xx) para `:account_webhook`** OU documentar honestamente at-most-once. NÃO afirmar "retry grátis". | Verificado: hoje webhooks account são **at-most-once com perda silenciosa** (ver B1). Decisão de produto, não "opcional diferida". |
| **D6** | **Gate do connection card e CTAs** | **`administrator?` para criar Webhook e Hook**; o card pode aparecer para `crm_admin`, mas as ações que chamam `WebhookPolicy`/`HookPolicy` exigem admin. Se quiser self-service `crm_admin`, exige overlay EE nas duas policies (fora do MVP). | `WebhookPolicy`/`HookPolicy` são **admin-only** hoje (verificado). Card que oferece ação que a API 403 é UX quebrada. |
| **D7** | **`Idempotency-Key` (Stripe-style) no MVP** | **Sim para writes sem `external_id`** (move/close/link). Persistir só 2xx; nunca 5xx. Claim de chave ANTES da ação (transação + estado `processing`). | Move/close não têm `external_id`; sem isso, retry duplica transição. |
| **D8** | **`updated_since` + tiebreak `id` no index de cards** | **Sim** (sync incremental confiável para n8n). | Sem cursor, polling re-escaneia e perde/duplica linhas sob edição concorrente. |
| **D9** | **Granularidade de escopo do token v1** | Expor todos os `crm_*` keys como checkboxes (`crm_view`, `crm_manage_cards`, `crm_move_cards`, `crm_manage_pipelines`, `crm_manage_ai`, `crm_view_reports`, `crm_admin`). | Já são as chaves nativas de `CustomRole::PERMISSIONS`. |
| **D10** | **n8n self-hosted em rede privada** | **Documentar como requisito: n8n precisa de URL HTTPS pública.** NÃO implicar allowlist por-conexão. | `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` é **global/processo** (verificado em `lib/safe_fetch.rb:39`); não há allowlist por-webhook. |

---

## 3. Arquitetura por pilar

### 3.1 Pilar A — Webhooks de saída (CRM → externo)

#### Abordagem
O ponto central: **eventos de CRM hoje não passam pelo dispatcher**. `Crm::Cards::Broadcaster` chama `ActionCableBroadcastJob` direto (só WebSocket); `WebhookListener` só está ligado ao `AsyncDispatcher`. Logo, é tudo **net-new** — não é "reuso end-to-end" como o design n8n sugeria.

3 camadas:
1. **Taxonomia:** adicionar constantes em `lib/events/types.rb`. Já existem `CRM_CARD_CREATED/UPDATED/MOVED/ARCHIVED` (verificado, linhas 66-69). Adicionar `CRM_CARD_WON/LOST/REOPENED` (MVP) e, fase 2, `CRM_CARD_VALUE_CHANGED`, `CRM_AI_SUGGESTED/AUTO_MOVED/HANDOFF`, `CRM_FOLLOW_UP_DUE/OVERDUE`.
2. **Emissão (corrigida — ver B2):** **NÃO emitir de `Crm::ActivityLogger#perform`** (está dentro de transação — verificado: `mover.rb:15`, `closer.rb:25`, `creator.rb:17` envolvem `ActivityLogger` em `ActiveRecord::Base.transaction`). Em vez disso, emitir via **`after_commit` em `Crm::Activity`** chamando `Crm::Webhooks::Emitter`, passando **IDs (não objetos AR)**. O Emitter usa um **allowlist explícito** mapeando as strings reais de `event_type` → constante de dispatcher, e faz **early-exit se nenhum webhook da conta assina o evento** (evita inundar a fila `:critical`).
3. **Fan-out + payload:** estender `WebhookListener` com um handler por evento CRM, reusando `deliver_account_webhooks` (verificado: linhas 110-116, já gera `delivery_id: SecureRandom.uuid`). Payload construído por **`Crm::Webhooks::PayloadBuilder` escrito do zero** (não subclasse do `Cards::PayloadBuilder`), default-deny de PII/IA.

#### O que REUSA do nativo
- `app/models/webhook.rb` (`ALLOWED_WEBHOOK_EVENTS` linha 32, `subscriptions` jsonb, `account.webhooks`)
- `app/listeners/webhook_listener.rb` (`deliver_account_webhooks` + filtro `subscriptions.include?`)
- `app/jobs/webhook_job.rb` + `lib/webhooks/trigger.rb` (HMAC `X-Chatwoot-Signature`, `X-Chatwoot-Timestamp`, `X-Chatwoot-Delivery`, `SafeFetch` SSRF)
- `app/dispatchers/async_dispatcher.rb` (já carrega `WebhookListener`; EE `enterprise/app/dispatchers/enterprise/async_dispatcher.rb` faz `super + [...]` — verificado, alcance EE OK)
- `app/services/crm/config.rb` (`Crm::Config.enabled?` lê `CRM_KANBAN_ENABLED` — verificado linha 5-6)

#### Modelo de dados / migrations
- **Nenhuma tabela nova no MVP.** `webhooks.subscriptions` já é jsonb livre.
- `event_id` estável derivado de `crm_activities.id` no payload; header opcional `X-Chatwoot-Event-Id` aditivo em `lib/webhooks/trigger.rb`.
- (Deferido) tabela `crm_webhook_deliveries` para replay UI — PR separado.

#### Eventos e envelope
```
POST {url_configurada}
Headers: X-Chatwoot-Signature: sha256=HMAC_SHA256(secret,"{ts}.{body}")
         X-Chatwoot-Timestamp, X-Chatwoot-Delivery (por tentativa)
         X-Chatwoot-Event-Id (estável, crm_activities.id) [opcional]
Body: { event:'crm.card.moved', event_id, account_id, timestamp,
        data:{...card estável, ids...}, changed_attributes:[...] }
```
**String canônica:** usar a forma pontilhada `crm.card.created` em **TODOS** os lugares (entrada de `ALLOWED_WEBHOOK_EVENTS`, valor de `subscriptions`, `payload[:event]`); o método do listener é `name.tr('.','_')` → `crm_card_created`. Spec deve assertar o alinhamento (senão zero entregas).

#### Segurança
- HMAC reusado as-is (per-webhook secret, `encrypts`).
- SSRF via `SafeFetch` (`lib/safe_fetch.rb`) — não burlar.
- **PII default-deny:** novo `PayloadBuilder` exclui por construção `email`, `phone_number`, owner email, `metadata['ai']`, `ai_summary`, `ai_value`. Spec obrigatório asserta ausência dessas chaves sem contexto de usuário.
- Allowlist de `event_type` (não denylist): pular `conversation_sync`, `follow_up_message_sent/failed`, `conversation_dedup_reuse`, `expected_close`.
- Estender `ALLOWED_WEBHOOK_EVENTS` condicionalmente em `Crm::Config.enabled?` para evitar subscriptions mortas em CE.

---

### 3.2 Pilar B — Tokens de API (externo → CRM)

#### Abordagem
Token **por-conta, escopado, revogável** (D1). A restrição decisiva (verificada): `enterprise/app/policies/crm_permissions.rb#crm_permission?` lê só `account_user.custom_role.permissions` e **`return true if custom_role.blank?`** (linha 15 — fallback de agente pleno = superusuário CRM). Owners sem `account_user` são negados. Logo o token deve resolver para um **`account_user` com `custom_role` gerenciado** cujas permissions = escopos do token.

Implementação: `Crm::IntegrationToken` (estilo `AgentBot`), `AccessTokenable`, com um **`AccountUser` oculto dedicado** (`role: agent`, flag `integration: true`) ligado a um **`CustomRole` gerenciado**. `allowed_current_user_type?` (verificado: linha 22, hoje só `User`/`AgentBot`) estendido; `EnsureCurrentAccountHelper` seta `Current.account_user` = `token.account_user`.

#### O que REUSA do nativo
- `app/models/access_token.rb` (`has_secure_token`, owner polimórfico)
- `app/models/concerns/access_tokenable.rb`
- `app/models/agent_bot.rb` (template de owner account-scoped)
- `app/controllers/concerns/access_token_auth_helper.rb` (linha 19, 22)
- `enterprise/app/models/custom_role.rb` (`PERMISSIONS` whitelist `crm_*`)
- `config/initializers/rack_attack.rb` (throttle DSL)
- `app/javascript/dashboard/routes/dashboard/settings/profile/AccessToken.vue` (padrão reveal-once)

#### Modelo de dados / migrations (aditivo)
- **NEW** `crm_integration_tokens`: `account_id`, `name`, `custom_role_id`, `account_user_id`, `created_by_id`, `last_used_at`, `status` (enum active/revoked). `include AccessTokenable`.
- **NEW coluna** `account_users.integration:boolean default false, index`.
- REUSA `access_tokens` (`owner_type='Crm::IntegrationToken'`) e `custom_roles` (um por token).
- Migration aditiva; rodar gate **`eager_load`** (anotar modelos).

#### Endpoints
```
GET    /api/v1/accounts/:id/crm/integration_tokens        (metadata, nunca o segredo)
POST   /api/v1/accounts/:id/crm/integration_tokens        (reveal-once)
DELETE /api/v1/accounts/:id/crm/integration_tokens/:id    (revoga, síncrono)
POST   /api/v1/accounts/:id/crm/integration_tokens/:id/rotate
```
Todos gated `crm_admin` via `Crm::IntegrationTokenPolicy` (OSS base + overlay EE).

#### Segurança — com os 4 blockers do review dobrados (ver §4)
- **Guard fail-closed (B-T1):** `restrict_integration_token_to_crm!` mapeia a ação requisitada → escopo `crm_*` explícito, default **deny**. Resolve o buraco de `close?` ausente no overlay EE estruturalmente.
- **Revogação atômica (B-T2):** numa única transação — `status=revoked` + `AccessToken.where(owner:).delete_all` (síncrono) + destruir `AccountUser` **antes/junto** do `CustomRole`. Auth path também checa `status == active`. Nunca deixar `account_user` com `custom_role` nil (senão vira superusuário pelo fallback).
- **CE não pode quebrar (B-T3):** referências a `Crm::IntegrationToken`/`CustomRole` nos helpers core ficam atrás de `prepend_mod_with`/`defined?` — confirmar fork EE-only ou documentar CE não-suportado.
- **Vazamento de agente (B-T4):** patch em **`Account#agents`** (verificado: `account.rb:130` = `users.where(account_users:{role: :agent})`) com `.where(account_users:{integration:false})`, scope `AccountUser.human`, e **suprimir callbacks de lifecycle** (`notify_creation`, `create_notification_setting`, presence, `Agents::DestroyJob`) para linhas `integration:true`.
- Reveal-once; `filter_parameter_logging` de `api_access_token`.
- Rate-limit per-token (Rack::Attack) keyed no header do token. Allowlist CRM-only **controller-based** (`params[:controller].start_with?('api/v1/accounts/crm/')`), **incluindo relatórios CRM em `/api/v2/.../reports`** que NÃO ficam sob `/crm/`.

---

### 3.3 Pilar C — API de entrada (o que sistemas externos chamam)

#### Abordagem
**Não construir API paralela.** Os controllers existentes `app/controllers/api/v1/accounts/crm/*.rb` já são token-autháveis. A lacuna é: idempotência, contrato estável, rate-limit, ergonomia (`external_id`), e fechar buracos de auditoria. Endurecer, não substituir.

#### O que REUSA do nativo
- `app/controllers/api/base_controller.rb`, `concerns/access_token_auth_helper.rb`, `concerns/ensure_current_account_helper.rb`
- `enterprise/app/policies/enterprise/crm/card_policy.rb` + `app/policies/crm/card_policy.rb`
- `app/controllers/api/v1/accounts/crm/{cards,pipelines,stages}_controller.rb`
- `app/services/crm/cards/{creator,mover,closer,filter_query,detail_payload_builder}.rb`
- Precedente `contacts.identifier` + `uniq_identifier_per_account_contact` para o upsert

#### Modelo de dados / migrations
- **NEW** `crm_cards.external_id:string` (nullable) + índice parcial único `[account_id, external_id] WHERE external_id IS NOT NULL` (`uniq_crm_cards_external_id_per_account`).
- `crm_cards.source` já existe — formalizar como tag do sistema originador.
- **NEW** `idempotency_keys`: `account_id`, `key`, `request_fingerprint` (sha256 method+path+body), `response_status`, `response_body` (jsonb), `locked_at`/estado `processing`, `created_at`. Único `[account_id, key]`. TTL 24h + job de limpeza.
- Validação `external_id` uniqueness scope account + cap 255 (memória: `ApplicationRecord` 255-cap aplica).

#### Endpoints (contrato v1)
```
POST   /crm/cards            create OU upsert (201 insert / 200 update). Honra Idempotency-Key.
PATCH  /crm/cards/:id        update (ver B-API3: status/value_cents removidos do contrato)
POST   /crm/cards/:id/move   {stage_id}                 (Idempotency-Key)
POST   /crm/cards/:id/close  {result:won|lost|reopen,value_cents,currency,lost_reason}
POST   /crm/cards/:id/link_conversation | link_contact
GET    /crm/cards?pipeline_id&stage_id&status&external_id&updated_since&page&per_page
GET    /crm/pipelines  |  /crm/pipelines/:id/stages
Headers: api_access_token (req), Idempotency-Key (opt) → resp Retry-After (429), Idempotency-Replayed
```

#### Segurança / blockers dobrados (ver §4)
- **Upsert atômico (B-API1):** `create_or_find_by!`/`upsert` + retry em `RecordNotUnique`; `rescue_from ActiveRecord::RecordNotUnique → 409 crm.card.external_id_conflict`.
- **Idempotência com lock (B-API2):** claim da linha PRIMEIRO em transação (`INSERT ... ON CONFLICT DO NOTHING` / `processing`), tratar "linha existe, resposta não gravada" como 409/425. Persistir só 2xx; nunca 5xx.
- **Bypass de auditoria (B-API3):** remover `:status` (e provavelmente `:value_cents`) de `update_params` no contrato de entrada, OU rotear transições de status pelo `Closer`. Hoje `PATCH status='won'` pula o `Closer` (sem `Crm::Activity` won/lost, sem lock de valor).
- Envelope de erro estável `{error:{code,message,details}}` via `rescue_from` em `crm/base_controller.rb`. Mapear `crm.stage.not_found` vs `crm.stage.wrong_pipeline`.
- Tenant isolation: todo lookup `external_id` scoped por `account_id`.

---

### 3.4 Pilar D — Camada n8n (Conexões / descoberta)

#### Abordagem
Cola de integração, sem transporte novo. Connection card `crm_n8n` em `config/integration/apps.yml` espelhando `crm_kanban_ai` (verificado linha 25-29) + `leadsquared` (verificado: `feature_flag: crm_integration` linha 288). **Não é credential store** — token vive em `crm_integration_tokens`, subscription em `webhooks`. O card faz deep-link para (1) UI de tokens CRM e (2) criador de Webhook pré-filtrado a eventos CRM.

#### O que REUSA
- `config/integration/apps.yml` + `app/models/integrations/hook.rb`
- `Integrations::HooksController` (app_id `crm_n8n`)
- Nó community Chatwoot do n8n já fala `api_access_token` — sem nó custom no MVP

#### Modelo de dados
- **Nenhuma tabela nova.** Linha `Integrations::Hook` (`hooks` table) criada ao conectar. `settings` jsonb guarda só display (base_url read-only) — **NÃO guardar URL server-callable** (evita herdar superfície SSRF do `api_base` de `crm_kanban_ai`).

#### Gate de feature (B-N1 — corrigido)
Dois sistemas distintos: `apps.yml feature_flag` → `account.feature_enabled?('crm_integration')` vs `Crm::Config.enabled?` (ENV `CRM_KANBAN_ENABLED`). **Não são automaticamente consistentes.** Decisão: reusar feature `crm_integration` para `App#active?`/`feature_flag` (card aparece onde `leadsquared` aparece) **E** guard server-side checando `Crm::Config.enabled?`. Documentar que **ambos** precisam estar ligados.

#### Segurança
- Trigger HMAC + verificação no lado n8n (snippet de doc rejeita timestamp velho + dedup por `event_id`).
- n8n self-hosted privado é bloqueado por `SafeFetch` (D10) — documentar como requisito de primeira classe.

---

## 4. Riscos transversais e mitigação (com blockers dos reviews)

| ID | Risco / Blocker | Severidade | Mitigação travada |
|----|-----------------|------------|-------------------|
| **B1** | **Claim de retry é FALSO.** Verificado: `application_job.rb:3` só tem `discard_on`; `trigger.rb:34` engole erros não-agent-bot via `handle_failure` (re-raise só p/ `:agent_bot_webhook` status 429/500, linha 126). 5xx/timeout em webhook account = **perda silenciosa at-most-once.** | **Alta** | D5: adicionar `retry_on` limitado p/ `:account_webhook` em `WebhookJob`/`Trigger` OU documentar at-most-once + confiar em idempotência do consumidor (`X-Chatwoot-Event-Id`). Decisão de produto explícita. |
| **B2** | **Bug de boundary de transação.** Verificado: `mover.rb:15`, `closer.rb:25`, `creator.rb:17` chamam `ActivityLogger` dentro de `ActiveRecord::Base.transaction`. Emitir dali → `EventDispatcherJob` (queue `:critical`) pode rodar ANTES do commit (lê estado stale ou dispara evento que rollback desfez) ou falhar `DeserializationError` (GlobalID de registro não-commitado) → discard silencioso. | **Alta** | Emitir via **`after_commit` em `Crm::Activity`**, passando **IDs** (account_id, card_id, activity_id, event, changed_attributes Hash serializável), listener recarrega por id. |
| **B3** | **Eventos-fonte ausentes.** Verificado: `closer.rb:63` emite `EVENT_TYPES[@result]` (strings reais `won`/`lost`/`reopen` — NÃO `reopened`); `value_changed` **não existe** como event_type (flui via `update` genérico); `follow_up_overdue` existe (`due_processor.rb:79`); `ai_handoff` (`handoff_executor.rb:131`), `ai_auto_moved`/`ai_suggested` (`suggestion_recorder.rb:48`). | **Alta** | Mapa do Emitter usa as **strings reais** (`won`,`lost`,`reopen`,`move`,`create`,`archive`,`ai_handoff`,`ai_auto_moved`,`ai_suggested`,`follow_up_overdue`). `value_changed` **fora do MVP** (D3) até instrumentar atividade dedicada. |
| **B4** | **PII default-leak.** `Crm::Cards::PayloadBuilder` inclui `email`/`phone_number`/`ai_summary` incondicionalmente; gating de IA depende de `Current.user` que não existe em emit account-scoped. | **Alta** | D4: `Crm::Webhooks::PayloadBuilder` **escrito do zero**, exclui PII/IA por construção. Spec asserta ausência de email/phone/ai. Flag `include_contact_pii` (schema + permitted param novos no Webhook) opt-in. |
| **B-T1** | **Least-privilege falso p/ `close`.** Verificado: overlay EE `card_policy.rb` define `index/show/create/update/move` mas **não `close?`** → cai no OSS `close?`=`update?`=visibilidade pura. Token `crm_view`-only PODE ganhar/perder card. | **Alta** | Guard **fail-closed** mapeando ação→escopo, default deny. Spec por ação (index/show/create/update/destroy/move/close/link_*/evaluate_ai/summarize). |
| **B-T2** | **Revogação não-imediata + escalada.** `dependent: :destroy_async` + `custom_role has_many account_users dependent: :nullify` → se CustomRole morre antes, `account_user.custom_role_id` vira nil → fallback `custom_role.blank? → true` = superusuário CRM. | **Alta** | Revogação síncrona atômica (§3.2); auth path checa `status active`; guard trata account_user de token com custom_role nil como **DENY**. |
| **B-T3** | **OSS-core referencia constante EE.** Helpers core editados referenciam `Crm::IntegrationToken`/`CustomRole` (EE-only) → `NameError` em build CE em toda request `api_access_token`. | **Alta** | `prepend_mod_with`/`defined?` guards ou confirmar fork EE-only documentado. |
| **B-T4** | **Agente backing vaza em superfícies core.** `Account#agents` (`account.rb:130`) usado por pickers/assignment/round-robin/reports/@mentions. Callbacks `after_create_commit`/`after_destroy` disparam infra real (presence, `Agents::DestroyJob`). | **Alta** | Patch `Account#agents` (`integration:false`), scope `AccountUser.human`, suprimir callbacks p/ `integration:true`. |
| **B-API1/2/3** | Upsert não-atômico (500 em `RecordNotUnique`); idempotência sem lock (double-write); `update` deixa setar `status=won/archived` direto (bypass de auditoria). | **Alta** | §3.3: `create_or_find_by!`+retry; claim-first + estado `processing`; strip `:status`/`:value_cents` do contrato de entrada. |
| **B-N1** | Gate de feature inconsistente (`crm_integration` feature vs `CRM_KANBAN_ENABLED` ENV). | **Alta** | §3.4: reusar `crm_integration` p/ visibilidade + guard `Crm::Config.enabled?`. Documentar dual-gate. |
| **B-N2** | Deep-link p/ criador de webhook 403 p/ usuário `crm_admin` não-admin (`WebhookPolicy`/`HookPolicy` admin-only — verificado). | **Alta** | D6: restringir ações a `administrator?`; não oferecer na UI ação que a API 403. |
| **R1** | **Tempestade de eventos / fila `:critical`.** Toda `Crm::Activity.create!` enfileiraria `EventDispatcherJob` mesmo sem webhook assinante; AI auto-move/bulk move amplificam; `:medium` compartilhado com webhooks core (timeout 5s pode saturar). | **Média** | Early-exit no Emitter (skip enqueue se nenhum webhook assina o evento); isolar entrega CRM em fila dedicada de prioridade menor. |
| **R2** | **SSRF / n8n privado.** `SafeFetch` bloqueia IPs privados; único escape `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` é **global** (verificado `safe_fetch.rb:39`). | **Média** | Não burlar. Documentar "URL HTTPS pública obrigatória" como Requirements de primeira classe (D10). |
| **R3** | **Replay window aspiracional.** Chatwoot é o emissor; freshness só vale se n8n verifica. | **Baixa** | Snippet de doc rejeita timestamp stale + dedup por `event_id`. |
| **R4** | **`event_id` não é 1:1 com evento lógico.** Um auto-move pode gerar `ai_auto_moved` + `move` (2 atividades) → 2 webhooks p/ uma transição. | **Média** | Definir "evento lógico" + auditar exactly-once por ação em closer/mover/suggestion_recorder; spec. |
| **R5** | i18n: CLAUDE.md = **só `en.yml` + `en.json`**, NÃO `pt_BR` (community-handled). Designs erram ao dizer "en + pt_BR". | **Baixa** | Editar só en. |

---

## 5. Sequência de sub-PRs em ondas

> Ordenado por **menor risco primeiro**. Cada onda é independentemente deployável e passa pelos gates (§6). Esforço: S/M/L/XL.

### Onda 1 — Fundação de entrada (menor risco, sem novos princípios de auth)
| PR | Escopo | Esforço | Dependências |
|----|--------|---------|--------------|
| **PR1.1** Upsert `external_id` | Migration `external_id`+índice parcial; validação modelo; `Creator`/`FilterQuery`/`DetailPayloadBuilder`; branch upsert atômico (`create_or_find_by!`+retry, 200 vs 201); `rescue_from RecordNotUnique→409`. Specs tenant-isolation. (B-API1) | **M** | — |
| **PR1.2** Envelope de erro + validação | `rescue_from` em `crm/base_controller.rb` → `{error:{code,message,details}}`; mapear `stage.not_found`/`wrong_pipeline`; **strip `:status`/`:value_cents`** do `update_params` (B-API3). | **S** | PR1.1 |

### Onda 2 — Webhooks de saída (trigger)
| PR | Escopo | Esforço | Dependências |
|----|--------|---------|--------------|
| **PR2.1** Taxonomia + bridge after_commit | Constantes MVP em `types.rb`; `Crm::Webhooks::Emitter` (allowlist strings reais, early-exit sem assinante); **emit via `after_commit` em `Crm::Activity` passando IDs** (B2/B3). Sem entrega ainda (assert dispatch). | **M** | — |
| **PR2.2** Fan-out + PayloadBuilder + whitelist + retry | Estender `ALLOWED_WEBHOOK_EVENTS` (gated `Crm::Config.enabled?`); handlers no `WebhookListener`; **`Crm::Webhooks::PayloadBuilder` do zero, PII-default-deny** (B4); header `X-Chatwoot-Event-Id`; **decidir retry (D5/B1)**. Spec: payload sem email/phone/ai; alinhamento string canônica. | **M** | PR2.1 |

### Onda 3 — Tokens escopados (action) — maior superfície de regressão
| PR | Escopo | Esforço | Dependências |
|----|--------|---------|--------------|
| **PR3.1** Modelo + auth plumbing | Migration `crm_integration_tokens` + `account_users.integration`; modelo `Crm::IntegrationToken` (managed CustomRole + AccountUser oculto, callbacks suprimidos — B-T4); estender `allowed_current_user_type?`/`EnsureCurrentAccountHelper` atrás de `prepend_mod_with` (B-T3); **guard fail-closed** CRM-only controller-based incl. reports v2 (B-T1). Specs: token escopado autoriza CRM, nega não-CRM, nega por escopo (close incluído). | **L** | — |
| **PR3.2** API de gestão + policy + revogação atômica | `integration_tokens_controller` (index/create/destroy/rotate); `Crm::IntegrationTokenPolicy` (OSS+EE, `crm_admin`); **revogação síncrona atômica** (B-T2); reveal-once; `filter_parameter_logging`; `last_used_at` throttled. | **M** | PR3.1 |
| **PR3.3** Idempotency-Key + rate-limit | `idempotency_keys` table+modelo; concern com **claim-first/lock** (B-API2, só 2xx); job de limpeza TTL; throttle per-token em `rack_attack.rb`. | **M** | PR3.1, PR1.1 |

### Onda 4 — UX e descoberta n8n (depende de Ondas 2+3)
| PR | Escopo | Esforço | Dependências |
|----|--------|---------|--------------|
| **PR4.1** UI de Tokens CRM | Vue3 `<script setup>` settings page: list/create(checkboxes escopo)/revoke/rotate; reveal-once copy box; snippet n8n; i18n en. | **M** | PR3.2 |
| **PR4.2** UI checkboxes CRM em Webhooks | Seção CRM no form de Webhook existente (gated `CRM_KANBAN_ENABLED` + admin); store/api; constante `CRM_WEBHOOK_EVENTS`. | **M** | PR2.2 |
| **PR4.3** Connection card `crm_n8n` | Hook em `apps.yml` (feature `crm_integration` — B-N1), logo, settings screen com catálogo + 2 CTAs deep-link (gate `administrator?` — D6/B-N2); guard `Crm::Config.enabled?`; i18n en; `updated_since` no index (D8). | **M** | PR4.1, PR4.2 |
| **PR4.4** Docs de integrador | `docs/integrations/n8n-crm.md`: payloads de cada evento, snippet de verificação HMAC (rejeita stale + dedup `event_id`), curl/n8n configs, **Requirements: URL HTTPS pública (R2/D10)**. | **S** | todas |

### Deferidos (PR separado, pós-MVP)
- `value_changed` + eventos IA + follow_up (fase 2, B3/D3).
- Tabela `crm_webhook_deliveries` + replay UI.
- Nó n8n community branded.

---

## 6. Gates de qualidade e plano de teste

### Gates obrigatórios (do workflow de deploy do fork)
1. **`eager_load` verde** — todo modelo novo (`Crm::IntegrationToken`, `IdempotencyKey`) anotado; especialmente os modelos EE sob `enterprise/` (B-T3).
2. **Teste visual** — antes do build vite/deploy Swarm.
3. **Build vite + deploy Swarm** conforme `chatwoot-crm-deploy-workflow`.
4. **Zero regressão core (CE e EE):** suíte de webhooks core (`message_created`/`conversation_*`) deve passar; CE build não pode dar `NameError` no auth path (B-T3).

### Specs por blocker (não-asseridos, **enforced**)
- **Webhooks:** payload trigger NÃO contém `email`/`phone`/`ai_summary`/`ai_value`/`conversation` por padrão (B4); `include_contact_pii=true` faz opt-in; emissão exactly-once por ação lógica (R4); alinhamento string canônica `ALLOWED_WEBHOOK_EVENTS`=`subscription`=`payload[:event]`; emit ocorre em `after_commit`, não mid-transaction (B2); rollback de transação NÃO dispara webhook.
- **Tokens:** token `crm_view`-only **NÃO** pode `close`/`move`/`create` (B-T1, por ação); revogação invalida imediatamente o segredo e NÃO deixa superusuário (B-T2); backing user NÃO aparece em `Account#agents`/assignment/reports (B-T4); CE build não referencia constante EE (B-T3); guard CRM-only nega conversas/contatos/admin e permite reports v2.
- **Entrada:** retries concorrentes de mesmo `external_id` → **exatamente um** card (B-API1); `Idempotency-Key` duplicado concorrente → **um** write (B-API2); `PATCH status=won` rejeitado ou roteado pelo `Closer` (B-API3); token de conta A NÃO faz upsert em card de conta B (tenant isolation); token sem `crm_manage_cards` → 403 em create/move/close.

### Teste real com workflow n8n (aceitação E2E)
1. **Setup:** n8n em URL HTTPS pública; mintar `Crm::IntegrationToken` escopado `crm_manage_cards`+`crm_move_cards`; armazenar como Header Auth (`api_access_token`).
2. **ACTION path:** nó HTTP Request → `POST /crm/cards` com `external_id` + `Idempotency-Key`; **forçar retry** do nó → assertar 1 card (200 no replay, header `Idempotency-Replayed`).
3. **TRIGGER path:** criar Webhook account assinando `crm.card.won`; nó Webhook do n8n recebe; mover card para stage won via dashboard → assertar POST recebido, assinatura HMAC válida, **sem PII**, `event_id` presente.
4. **Dedup:** simular retry de entrega (mesma `event_id`, `delivery_id` diferente) → n8n colapsa.
5. **Negativos:** token `crm_view`-only → 403 em create/move/close; n8n em IP privado → entrega bloqueada por SafeFetch (confirmar log, documentar).
6. **Revogação:** `DELETE` token → próxima chamada n8n → 401 imediato.

---

### Arquivos reais citados (todos verificados neste repo)
`/root/docker-stacks/build/chatwoot-campaign-v4.14.1/`
- `lib/webhooks/trigger.rb` (L3,5,26,29,31,34,126), `app/jobs/application_job.rb` (L3), `app/jobs/webhook_job.rb`
- `app/services/crm/cards/{mover.rb:15,43, closer.rb:25,60,63, creator.rb:17,23}`, `app/services/crm/ai/{suggestion_recorder.rb:48, handoff_executor.rb:131}`, `app/services/crm/follow_ups/due_processor.rb:79`
- `app/services/crm/config.rb:5`, `app/services/crm/cards/payload_builder.rb`
- `app/controllers/concerns/access_token_auth_helper.rb:19,22`, `app/controllers/concerns/ensure_current_account_helper.rb`, `app/controllers/api/base_controller.rb`, `app/controllers/api/v1/accounts/crm/{base_controller,cards,pipelines,stages}_controller.rb`
- `app/models/account.rb:130`, `app/models/{access_token,agent_bot,webhook.rb:32}`, `app/models/concerns/access_tokenable.rb`
- `enterprise/app/policies/crm_permissions.rb:9,15`, `enterprise/app/policies/enterprise/crm/card_policy.rb` (sem `close?`), `enterprise/app/models/custom_role.rb`
- `app/policies/{webhook_policy.rb:3, hook_policy.rb:2}`, `app/listeners/webhook_listener.rb:110,116`, `lib/events/types.rb:66-69`
- `app/dispatchers/async_dispatcher.rb`, `enterprise/app/dispatchers/enterprise/async_dispatcher.rb:2-3`
- `lib/safe_fetch.rb:39`, `config/integration/apps.yml:25,288`, `config/initializers/rack_attack.rb`
- `app/javascript/dashboard/routes/dashboard/settings/profile/AccessToken.vue`