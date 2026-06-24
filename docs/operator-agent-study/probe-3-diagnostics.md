# Pilar 3 - Diagnostico e observabilidade

Sondagem de viabilidade aterrada no codigo real do fork Chatwoot v4.15.1 EE/white-label. Escopo: diagnostico read-only para um futuro "Agente Operacional Autonomo", sem implementar a feature.

## Resumo executivo

Diagnostico e observabilidade e a melhor cunha inicial: ha muitos sinais ja persistidos ou consultaveis, a maioria e read-only, e os riscos de regressao sao menores que em pilares de operacao/escrita. O principal cuidado e que parte dos sinais vive em Redis/Sidekiq e parte em tabelas Rails; ainda falta uma camada de correlacao por conta/conversa/evento para transformar isso em respostas confiaveis em linguagem natural.

Achados quantitativos:

- Jobs: 149 arquivos de job no total, sendo 117 em `app/jobs/**/*.rb` e 32 em `enterprise/app/jobs/**/*.rb`.
- Filas declaradas: 16 filas em `config/sidekiq.yml:17`, com prioridade ordenada de `critical` ate `action_mailbox_incineration`.
- Distribuicao de `queue_as`: `low=53`, `scheduled_jobs=31`, `default=22`, `medium=14`, `high=3`, `critical=2`, `purgable=4`, `async_database_migration=5`, `mailers=1`, `deferred=1`, `housekeeping=3`, `sem queue_as=10`.
- Cron: 21 entradas em `config/schedule.yml`, incluindo IMAP a cada minuto, atribuicao periodica, import purge, CRM follow-up, sync de reunioes, webhooks de calendario e campanhas de email.
- Modelos de canal: 15 arquivos relacionados a canais em `app/models/channel/**`, `app/models/concerns/channelable.rb` e overlay EE.
- Servicos ja existentes por dominio: calendario 13, entrega de mensagem 32, auto-assignment 9, webhook 10, Autonomia 34.
- Feature flags de conta: 63 entradas em `config/features.yml`, mapeadas para `accounts.feature_flags` por `app/models/concerns/featurable.rb`.

## Sinais ja existentes

### Jobs e filas

O Rails usa Sidekiq em desenvolvimento, staging e producao (`config/environments/development.rb`, `staging.rb`, `production.rb`). A configuracao central esta em `config/sidekiq.yml:5-39`: concorrencia via `SIDEKIQ_CONCURRENCY`, `max_retries: 3` e 16 filas ordenadas. A UI do Sidekiq esta montada em `config/routes.rb:874-916` como `/monitoring/sidekiq`, protegida por autenticacao de `super_admin`.

O cron e carregado por `config/initializers/sidekiq.rb:35-50` via `Sidekiq::Cron::Job.load_from_hash!`. O arquivo `config/schedule.yml` tem 21 entradas. Sinais diretamente uteis para diagnostico:

- `trigger_imap_email_inboxes_job` a cada minuto (`config/schedule.yml:23-27`).
- `periodic_assignment_job` a cada 30 minutos (`config/schedule.yml:58-62`).
- `crm_meeting_sync_sweep_job` a cada 15 minutos (`config/schedule.yml:102-108`).
- `crm_calendar_subscription_renewal_job` a cada 6 horas, gated por `CRM_CALENDAR_WEBHOOKS_ENABLED` (`config/schedule.yml:110-115`).
- `crm_follow_up_due_job`, `crm_ai_stale_cards_job`, `crm_ai_auto_followup_scan_job` para CRM/AI (`config/schedule.yml:84-121`).

Jobs relevantes encontrados:

- Webhooks/eventos: 15 arquivos (`app/jobs/webhooks/*`, `app/jobs/webhook_job.rb`, `app/jobs/agent_bots/webhook_job.rb`, `enterprise/app/jobs/enterprise/webhooks/whatsapp_events_job.rb`).
- Calendario CRM: 3 jobs (`app/jobs/crm/calendar/subscription_renewal_job.rb`, `app/jobs/crm/calendar/webhook_sync_job.rb`, `app/jobs/crm/meetings/sync_sweep_job.rb`).
- Auto-assignment: 2 jobs (`app/jobs/auto_assignment/assignment_job.rb`, `app/jobs/auto_assignment/periodic_assignment_job.rb`).
- Entrega/envio: 11 jobs, incluindo `SendReplyJob`, `ConversationReplyEmailJob`, `Webhooks::CrmDeliveryJob`, campanhas de email/WhatsApp e Autonomia chunked delivery.
- Autonomia agents: 7 jobs em `app/jobs/autonomia/agents/**`.

Como inspecionar estado/falhas hoje:

- Sidekiq Web: filas, scheduled, retry e dead set via `/monitoring/sidekiq` para super admin.
- Redis/Sidekiq API: possivel ler `Sidekiq::Queue`, `RetrySet`, `DeadSet`, `ScheduledSet` em um endpoint interno futuro; ja existe um exemplo simples de leitura de fila em `lib/tasks/sidekiq_tasks.rake:1-16`.
- Health basico: `app/controllers/api_controller.rb:4-24` retorna status de Redis e Postgres, mas nao expoe lag de fila, retries, dead jobs ou jobs por conta.

Lacunas:

- Nao ha indice persistido de job por `account_id`; ActiveJob serializa argumentos, mas o formato varia por job.
- Nao ha "correlation id" padrao entre request, dispatcher event, job, mensagem e webhook.
- Falhas ficam principalmente em Sidekiq/Sentry/logs; nem todo dominio grava erro estruturado em tabela propria.

### Webhooks

Configuracao persistida existe em `webhooks`:

- Tabela: `db/schema.rb:2117-2128` com `account_id`, `inbox_id`, `url`, `webhook_type`, `subscriptions`, `name`, `secret`, `include_contact_pii`.
- Modelo: `app/models/webhook.rb:22-60`.
- Eventos core: 12 eventos (`conversation_status_changed`, `conversation_updated`, `conversation_created`, `contact_created`, `contact_updated`, `message_created`, `message_updated`, `webwidget_triggered`, `inbox_created`, `inbox_updated`, `conversation_typing_on`, `conversation_typing_off`) em `app/models/webhook.rb:33-35`.
- Eventos CRM: 6 eventos (`crm.card.created`, `crm.card.moved`, `crm.card.won`, `crm.card.lost`, `crm.card.reopened`, `crm.card.archived`) em `app/models/webhook.rb:40-41`, expostos somente se `Crm::Config.enabled?` (`app/models/webhook.rb:46-50`).

Entrega:

- `WebhookListener` monta payloads e enfileira `WebhookJob` para account/API inbox webhooks (`app/listeners/webhook_listener.rb:167-188`).
- Webhooks CRM usam `Webhooks::CrmDeliveryJob` com `delivery_id: SecureRandom.uuid` (`app/listeners/webhook_listener.rb:147-150`).
- `WebhookJob` chama `Webhooks::Trigger.execute` (`app/jobs/webhook_job.rb:1-6`).
- `Webhooks::Trigger` envia via `SafeFetch`, adiciona `X-Chatwoot-Delivery`, `X-Chatwoot-Event-Id` e assinatura HMAC quando ha `secret` (`lib/webhooks/trigger.rb:48-73`).
- Core webhooks sao at-most-once: falha e tratada/logada e nao re-raise para retry (`lib/webhooks/trigger.rb:31-39`).
- Webhooks CRM tem retry bounded em 5xx/transport: `retry_on Webhooks::Trigger::RetryableError`, 4 tentativas (`app/jobs/webhooks/crm_delivery_job.rb:18-29`).
- Agent bot webhooks tem retry especifico em 429/500 por 3 tentativas (`app/jobs/agent_bots/webhook_job.rb:1-15`).

O que falta:

- Nao existe tabela `webhook_deliveries`/`WebhookDelivery`. Busca em `db/migrate`, `app`, `lib`, `enterprise` nao encontrou delivery persistido; ha somente `delivery_id` em headers e comentarios citando "future deliveries table" em `app/jobs/webhooks/crm_delivery_job.rb:21-24`.
- Nao ha historico consultavel de ultima entrega, status HTTP, latencia, corpo de erro ou numero de tentativas por webhook.
- Para diagnostico, hoje so da para responder "webhook configurado/assinando evento?", "ha jobs em retry/dead?" e "ha delivery_id em logs/consumidor externo?", nao "qual foi a ultima falha desse webhook?" sem logs externos.

### Integracoes e canais

Estados/tokens de canal ja existem e sao bons sinais read-only:

- `Channel::Instagram`: `access_token`, `expires_at`, `instagram_id`, `Reauthorizable`, refresh via `Instagram::RefreshOauthTokenService` (`app/models/channel/instagram.rb:1-74`).
- `Channel::FacebookPage`: `page_access_token`, `user_access_token`, `instagram_id`, subscribe/unsubscribe e `Reauthorizable` (`app/models/channel/facebook_page.rb:1-68`).
- `Channel::Whatsapp`: `provider`, `provider_config`, templates, `message_templates_last_updated`, setup/teardown webhook, `voice_enabled?`, `calling_enabled`, `webhook_verify_token`; falha de setup chama `prompt_reauthorization!` (`app/models/channel/whatsapp.rb:20-149`).
- `Channel::Email`: IMAP/SMTP, `provider`, `provider_config`, `verified_for_sending`, campos de calendario (`calendar_enabled`, `calendar_scope_granted`, `calendar_identity`, `calendar_shared`) em `db/schema.rb:673-705` e helpers em `app/models/channel/email.rb:64-110`.
- `Channel::Tiktok`: `access_token`, `refresh_token`, `expires_at`, `refresh_token_expires_at`, `business_id`, refresh via `Tiktok::TokenService` (`app/models/channel/tiktok.rb:1-44`).
- `Channel::Api`: `webhook_url`, `hmac_mandatory`, `secret`, `additional_attributes`, marca de WhatsApp API em `additional_attributes` (`app/models/channel/api.rb:22-102`).

O estado de reautorizacao e um sinal forte:

- `Reauthorizable` guarda contagem e flag em Redis: `AUTHORIZATION_ERROR_COUNT` e `REAUTHORIZATION_REQUIRED` (`app/models/concerns/reauthorizable.rb:19-48`, `lib/redis/redis_keys.rb:51-52`).
- Transicoes disparam evento de inbox se `ENABLE_INBOX_EVENTS` estiver ligado (`app/models/inbox.rb:221-228`).

Lacunas:

- `reauthorization_required?` e contador vivem em Redis, nao em tabela; perdem historico e exigem acesso Redis.
- Nem todo provedor tem expiracao persistida equivalente: Facebook tem tokens sem `expires_at`; Instagram/TikTok tem expiracao; Email guarda `provider_config.expires_on`; WhatsApp depende de `provider_config`.
- Checagens ativas de credencial/webhook existem em alguns dominios, mas chamar provedores em diagnostico deve ser opcional e gated para nao criar custo/risco.

### Calendario S7

Este e o conjunto mais maduro para diagnostico read-only.

Dados consultaveis:

- `crm_calendar_sync_states` em `db/schema.rb:1058-1075`: `account_id`, `inbox_id`, `provider`, `channel_id`, `resource_id`, `verification_token`, `expires_at`, `status`, `last_notified_at`, `metadata`.
- Modelo `Crm::CalendarSyncState`: enums `provider: google/microsoft`, `status: active/expired/failed`, escopo `renewable`, helper `expiring_before` (`app/models/crm/calendar_sync_state.rb:5-23`).
- Email inbox calendar flags: `calendar_enabled`, `calendar_scope_granted`, `calendar_identity`, `calendar_shared` (`db/schema.rb:699-703`).
- Endpoint read-only de calendario: `Api::V1::Accounts::Crm::CalendarController#events` e `#available_slots`, com `policy_scope(::Inbox)` e Pundit no mesmo fluxo (`app/controllers/api/v1/accounts/crm/calendar_controller.rb:1-25`, `118-125`).
- Free/busy Google: `Google::FreeBusyService` chama `/freeBusy`, timeout 15/30s, retorna `[]` em erro best-effort ou levanta em modo strict (`app/services/google/free_busy_service.rb:7-79`).
- Free/busy Microsoft: `Microsoft::FreeBusyService` chama Graph `/me/calendar/getSchedule`, idem (`app/services/microsoft/free_busy_service.rb:8-90`).
- `Crm::Meetings::AvailabilityService` adiciona cache de 15 min, modo strict para booking, disponibilidade por agente em mailbox compartilhada (`app/services/crm/meetings/availability_service.rb:7-164`).
- External events read-only: cache 30 min, max 100 eventos, dedupe contra `crm_meetings.external_event_id` (`app/services/crm/calendar/external_events_service.rb:1-117`).

Sync/push:

- `Crm::Calendar::SubscriptionManager` cria/renova Google/Microsoft, usa advisory lock por inbox e persiste `Crm::CalendarSyncState` (`app/services/crm/calendar/subscription_manager.rb:23-43`, `72-119`).
- Webhook publico valida `channel_id` + `verification_token`, atualiza `last_notified_at` e enfileira `WebhookSyncJob`; responde 200/202 mesmo quando desabilitado (`app/controllers/webhooks/crm_calendar_controller.rb:1-60`).
- `SubscriptionRenewalJob` roda apenas se `CRM_CALENDAR_MEETINGS_ENABLED` e `CRM_CALENDAR_WEBHOOKS_ENABLED` (`app/jobs/crm/calendar/subscription_renewal_job.rb:15-29`).
- `WebhookSyncJob` re-sincroniza reunioes agendadas de uma mailbox, janela -1 dia/+60 dias (`app/jobs/crm/calendar/webhook_sync_job.rb:15-35`).
- Pull sweep `SyncSweepJob` reconcilia proximos 7 dias, max 500 (`app/jobs/crm/meetings/sync_sweep_job.rb:15-35`).

Lacunas:

- Nao ha historico de cada chamada free/busy/sync; erros sao logs e retorno `[]` no caminho de display.
- `Crm::Config.calendar_meetings_enabled?` e instalacao-wide (`CRM_CALENDAR_MEETINGS_ENABLED`), nao por conta (`app/services/crm/config.rb:9-15`).
- Falta expor um resumo de "calendar readiness" por inbox sem tocar provedor.

### Entrega de mensagem

O modelo `Message` ja tem os campos principais:

- `status` enum: `sent`, `delivered`, `read`, `failed` (`app/models/message.rb:87-103`).
- `source_id` para id externo do canal (`app/models/message.rb:23`, indice em `db/schema.rb:1819`).
- `content_attributes` com accessor `external_error`, alem de `in_reply_to_external_id`, `is_unsupported`, etc. (`app/models/message.rb:111-113`).
- `external_source_ids` jsonb para casos como Slack (`app/models/message.rb:115`).
- `SendReplyJob` roteia canal -> service (`app/jobs/send_reply_job.rb:4-30`).

Atualizacao de status/erro:

- `Messages::StatusUpdateService` valida status, impede regressao `read -> delivered` e grava `external_error` apenas em `failed` (`app/services/messages/status_update_service.rb:1-33`).
- `Conversations::UpdateMessageStatusJob` marca mensagens anteriores como `delivered/read` (`app/jobs/conversations/update_message_status_job.rb:1-21`).
- Facebook e Instagram gravam `failed` com erro externo quando API retorna erro; Instagram erro 190 aciona `authorization_error!` (`app/services/facebook/send_on_facebook_service.rb:16-31`, `app/services/instagram/base_send_service.rb:56-79`).
- WhatsApp marca erro de template invalido (`app/services/whatsapp/send_on_whatsapp_service.rb:17-43`).
- Twilio/SMS delivery status localiza mensagem por `source_id` e grava `failed` com `external_error` (`app/services/twilio/delivery_status_service.rb:1-70`).
- Email grava `source_id` do SMTP/Graph e marca `failed` em exception (`app/services/email/send_on_email_service.rb:10-47`).

Lacunas:

- Nem todos os canais gravam a mesma granularidade de erro.
- `source_id` e `external_error` sao por mensagem, mas nao ha tabela de tentativas por mensagem.
- Logs ainda podem conter payloads de canal em alguns pontos; diagnostico deve usar `external_error`/status e mascarar conteudo sensivel.

### Conversa, inbox e atribuicao

Conversa:

- `Conversation.status`: `open`, `resolved`, `pending`, `snoozed` (`app/models/conversation.rb:75`).
- Campos diagnosticos: `assignee_id`, `assignee_agent_bot_id`, `team_id`, `waiting_since`, `first_reply_created_at`, `last_activity_at`, `priority`, `cached_label_list` (`db/schema.rb:911-954`).
- Conversas com bot ativo comecam `pending` (`app/models/conversation.rb:284-291`).
- Mudancas relevantes disparam eventos se atributos permitidos mudam (`app/models/conversation.rb:308-324`).

Inbox:

- `enable_auto_assignment`, `auto_assignment_config`, `working_hours_enabled`, `timezone`, `allow_messages_after_resolved` em `app/models/inbox.rb:7-24`.
- `assignable_agents` = membros do inbox + administradores (`app/models/inbox.rb:180-182`).
- `auto_assignment_v2_enabled?` depende de `account.feature_enabled?('assignment_v2')` (`app/models/inbox.rb:217-219`).

Atribuicao:

- V1 legacy roda em `AutoAssignmentHandler` quando conversa abre e inbox permite auto-assignment (`app/models/concerns/auto_assignment_handler.rb:11-27`).
- V2 coalesce por inbox em Redis (`AUTO_ASSIGNMENT_IN_FLIGHT`) e roda `AutoAssignment::AssignmentJob` (`app/jobs/auto_assignment/assignment_job.rb:1-53`).
- `AssignmentService` busca conversas `unassigned.open`, ordena por politica (`earliest_created` ou `longest_waiting`), filtra agentes por time/rate limit/capacidade EE e seleciona round-robin/balanced (`app/services/auto_assignment/assignment_service.rb:4-123`, `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb:16-28`).
- Round robin usa Redis list `ROUND_ROBIN_AGENTS:%<inbox_id>d` (`app/services/auto_assignment/inbox_round_robin_service.rb:1-61`).
- EE adiciona capacidade por agente/inbox (`enterprise/app/services/enterprise/auto_assignment/capacity_service.rb:1-24`) e balanced selector por menor carga (`enterprise/app/services/enterprise/auto_assignment/balanced_selector.rb:1-25`).

Lacunas:

- Nao ha log/tabela de "por que esta conversa nao foi atribuida". Da para recalcular parte da decisao, mas nao provar o historico.
- Estado round-robin e in-flight ficam em Redis; diagnostico precisa ler Redis ou limitar-se a sinais de DB.
- Conflitos entre automacoes e auto-assignment podem ser inferidos por regras ativas + eventos, mas nao ha timeline dedicada.

### Automation rules

Sinais persistidos:

- `automation_rules` tem `account_id`, `name`, `description`, `event_name`, `conditions`, `actions`, `active` (`db/schema.rb:267-277`).
- Modelo valida atributos de condicao/acao permitidos e inclui `Reauthorizable` (`app/models/automation_rule.rb:20-47`).
- Listener roda em eventos de conversa e mensagem, ignora eventos causados por AutomationRule para reduzir loop (`app/listeners/automation_rule_listener.rb:39-56`, `73-88`).
- `ConditionsFilterService` avalia regra contra conversa/contato/mensagem e desativa via `authorization_error!` quando validacao falha (`app/services/automation_rules/conditions_filter_service.rb:25-52`).
- `ActionService` aplica acoes sequenciais; mensagens automatizadas recebem `content_attributes.automation_rule_id` (`app/services/automation_rules/action_service.rb:9-21`, `43-54`).

Lacunas:

- Nao ha tabela de execucoes de automation rule com match/no-match, erro por acao ou latencia.
- Diagnostico de conflito hoje sera estatico/inferido: regras ativas, eventos iguais, acoes antagonicas (`assign_agent` vs `remove_assigned_agent`, `pending_conversation` vs `open_conversation`, `send_message` em cascata etc.).

### Features e flags por conta

O sistema de flags de conta existe e e maduro:

- `accounts.feature_flags` bigint (`app/models/account.rb:1-16`).
- `Featurable` le `config/features.yml`, cria bits via FlagShihTzu e expoe `feature_enabled?`, `all_features`, `enabled_features`, `disabled_features` (`app/models/concerns/featurable.rb:1-70`).
- `config/features.yml` tem 63 features; relevantes aqui: `automations`, `crm`, `assignment_v2`, `advanced_assignment`, `channel_instagram`, `channel_tiktok`, `channel_voice`, `whatsapp_campaign`, `captain_tasks`, `conversation_unread_counts`.
- Frontend referencia as flags em `app/javascript/dashboard/featureFlags.js:1-50`.

Custom flags fora do Featurable:

- CRM Kanban e calendario usam ENV: `CRM_KANBAN_ENABLED`, `CRM_CALENDAR_MEETINGS_ENABLED`, simulate flags (`app/services/crm/config.rb:1-28`).
- Autonomia Agents usa ENV master `AUTONOMIA_AGENTS_ENABLED` + `accounts.internal_attributes['autonomia_agents_enabled']`, com opcao global por credencial de IA (`app/services/autonomia/agents/config.rb:135-200`).
- `Api::V1::Accounts::Autonomia::BaseController` ja faz gate por feature e restringe a administradores da conta (`app/controllers/api/v1/accounts/autonomia/base_controller.rb:1-22`).

Lacunas:

- O operador autonomo deve consolidar flags de tres fontes: `feature_flags`, `internal_attributes` e ENV.
- Nem toda flag e por conta; diagnostico deve deixar claro se um bloqueio e global ou tenant-specific.

## Servicos de diagnostico propostos

Formato comum recomendado: `subject`, `checks`, `status` (`ok`, `warning`, `critical`, `unknown`), `evidence`, `recommended_actions`. Todos read-only, gated por ENV novo e Pundit/escopo de conta.

### 1. `account_readiness`

Subject: conta.

Checks:

- Features relevantes ligadas/desligadas (`Account#enabled_features`, `Autonomia::Agents::Config.enabled?(account)`, `Crm::Config.enabled?`).
- Presenca de credencial OpenAI resolvivel para Autonomia/CRM AI (`Crm::Ai::CredentialResolver`, ja usado por Autonomia).
- Contagem de inboxes por canal, inboxes sem membros, inboxes com `reauthorization_required?`.
- Health basico de Redis/Postgres via mesma logica de `ApiController#index`.

Status:

- `critical`: conta sem Redis/Postgres ok, ou recurso solicitado bloqueado por flag global.
- `warning`: feature de conta off, inbox sem membros, canal pedindo reautorizacao.
- `ok`: flags e recursos minimos presentes.

Recommended actions:

- Ligar feature no lugar correto (Featurable vs `internal_attributes` vs ENV).
- Reautorizar canal.
- Adicionar membros ao inbox.

Esforco: 1-2 dias. Baixo risco; quase todo dado ja existe.

### 2. `queue_health`

Subject: instalacao, fila, job class ou inbox/account quando inferivel.

Checks:

- Tamanho e latencia das filas Sidekiq (`critical`, `high`, `default`, `low`, `scheduled_jobs`).
- Jobs em retry/dead filtrados por classe relevante (`SendReplyJob`, `WebhookJob`, `Webhooks::CrmDeliveryJob`, `AutoAssignment::AssignmentJob`, `Crm::Calendar::*`).
- Cron carregado vs `config/schedule.yml`.

Status:

- `critical`: dead jobs recentes em classes de entrega/assignment/calendario; fila `high`/`critical` acumulada.
- `warning`: retry set crescendo, cron ausente, scheduled atrasado.
- `unknown`: nao foi possivel mapear job para conta.

Recommended actions:

- Abrir Sidekiq Web super admin.
- Reprocessar job quando seguro.
- Verificar Redis/Sidekiq workers/concurrency.

Esforco: 2-4 dias. Risco medio por isolamento: sem correlacao por conta, diagnostico deve evitar expor jobs de outros tenants.

### 3. `instagram_inbox`

Subject: inbox Instagram direto ou Facebook Page com `instagram_id`.

Checks:

- Canal existe, `instagram_id` presente, token presente/expiracao (`Channel::Instagram#expires_at`).
- `reauthorization_required?` e `authorization_error_count`.
- Ultimas mensagens outgoing no inbox com `status: failed` e `external_error`.
- Jobs `Webhooks::InstagramEventsJob` em retry/dead quando possivel.
- Assinatura de webhook inferida por modelo (`after_create_commit :subscribe`), sem chamada ativa por default.

Status:

- `critical`: reauthorization required, token expirado sem refresh, muitas mensagens failed recentes.
- `warning`: sem mensagens recentes, source_id ausente em outgoing antigo, webhook job em retry.
- `ok`: token/reauth ok e sem falhas recentes.

Recommended actions:

- Reautorizar Instagram.
- Testar mensagem controlada.
- Conferir app/permissions Meta quando erro 190.

Esforco: 1-2 dias para modo read-only; 3-5 dias se incluir teste ativo opcional.

### 4. `calendar_inbox`

Subject: inbox de email com calendario Google/Microsoft.

Checks:

- `Channel::Email` com `calendar_enabled?`, `calendar_scope_granted?`, `google?`/`microsoft?`.
- `crm_calendar_sync_states`: provider, status, `expires_at`, `last_notified_at`.
- `CRM_CALENDAR_MEETINGS_ENABLED`, `CRM_CALENDAR_WEBHOOKS_ENABLED`, simulate flags.
- Presenca de `crm_meetings.scheduled` com `external_event_id`.
- Free/busy opcional em modo seguro: somente quando solicitado, com timeout curto e sem cache poisoning.

Status:

- `critical`: calendario habilitado sem scope, sync state `failed/expired`, assinatura expirada com webhooks on.
- `warning`: webhooks off mas calendario on; `last_notified_at` muito antigo; simulate ativo fora de ambiente esperado.
- `ok`: inbox elegivel, sync state ativo/fresco, pull sweep habilitado.

Recommended actions:

- Reautorizar email com escopo de calendario.
- Ligar/desligar `CRM_CALENDAR_WEBHOOKS_ENABLED` conforme dominio verificado.
- Rodar renewal/sync manual via job interno se necessario.

Esforco: 1-3 dias. Alto ROI: dados ja estao estruturados e por conta/inbox.

### 5. `message_delivery`

Subject: mensagem, conversa ou inbox.

Checks:

- `Message.status`, `source_id`, `content_attributes.external_error`, canal, tipo, privado/publico.
- Janela de resposta (`Conversation#can_reply?`) para WhatsApp/template.
- Ultimas N mensagens outgoing failed por inbox/conversa.
- `SendReplyJob`/jobs de delivery em retry/dead quando mapeavel.

Status:

- `critical`: mensagem `failed`, `external_error` presente, canal em reauthorization required.
- `warning`: outgoing sem `source_id` apos janela esperada, status `sent` antigo em canal que deveria confirmar entrega.
- `ok`: delivered/read ou sent recente sem erro.

Recommended actions:

- Reautorizar canal.
- Corrigir template/parametros.
- Reenviar manualmente quando o canal permitir.

Esforco: 1-2 dias. Baixo risco; dados estao em `messages`.

### 6. `webhook_delivery`

Subject: webhook de conta/inbox/evento.

Checks:

- Webhook configurado, URL valida, assinatura/secret presente, `subscriptions` contem evento.
- Diferenciar core at-most-once vs CRM retryable.
- Procurar jobs `WebhookJob`, `AgentBots::WebhookJob`, `Webhooks::CrmDeliveryJob` em retry/dead por URL/payload quando possivel.
- Validar `include_contact_pii` e tipo (`account_type` vs `inbox_type`).

Status:

- `critical`: URL invalida, webhook sem subscription relevante, jobs CRM mortos/retry esgotado.
- `warning`: core webhook sem historico persistido; sem secret; include PII ligado.
- `unknown`: ultima entrega nao rastreavel por falta de tabela.

Recommended actions:

- Corrigir URL/subscription.
- Habilitar secret/HMAC.
- Para CRM, deduplicar consumidor por `X-Chatwoot-Event-Id`.
- Criar `webhook_deliveries` antes de prometer historico completo.

Esforco: 1-2 dias para readiness; 5-8 dias se adicionar tabela de deliveries.

### 7. `assignment_decision`

Subject: conversa ou inbox.

Checks:

- Conversa `open`, `assignee_id` nil, `team_id`, `waiting_since`.
- Inbox `enable_auto_assignment`, `assignment_v2`, assignment policy, membros disponiveis.
- Online agents via `OnlineStatusTracker`; round-robin list `ROUND_ROBIN_AGENTS`.
- EE: capacidade por `AgentCapacityPolicy`/`InboxCapacityLimit`, `advanced_assignment`.
- `AUTO_ASSIGNMENT_IN_FLIGHT` por inbox.

Status:

- `critical`: nenhum agente elegivel, inbox sem membros, assignment desligado.
- `warning`: todos sem capacidade/offline, team nao permite auto-assign, job in-flight travado perto do TTL.
- `ok`: ha agente elegivel e mecanismo ligado.

Recommended actions:

- Adicionar membros/capacidade.
- Ligar `enable_auto_assignment` ou `assignment_v2`.
- Ajustar team/assignment policy.

Esforco: 3-5 dias. Medio risco porque parte da decisao e recalculada e nao historica.

### 8. `automation_conflict`

Subject: conta, conversa ou regra.

Checks:

- Regras ativas por `event_name`.
- Condicoes sobre os mesmos atributos e acoes antagonicas.
- Acoes que geram mensagem (`send_message`, `send_attachment`) em eventos `message_created`.
- Regras com `authorization_error_count`/`reauthorization_required?`.
- Mensagens recentes com `content_attributes.automation_rule_id`.

Status:

- `critical`: regra ativa invalida/desautorizada, loop provavel em `message_created -> send_message`.
- `warning`: multiplas regras no mesmo evento alterando status/assignee/team de forma conflitante.
- `ok`: regras ativas sem conflito estatico obvio.

Recommended actions:

- Desativar/ajustar regra especifica.
- Mover acao para evento menos recursivo.
- Adicionar condicao de guarda.

Esforco: 3-6 dias. Comeca com analise estatica; historico real exigiria tabela de execucoes.

## Veredito

Recomendacao: comecar pelo Pilar 3, em modo read-only, com 4 diagnosticos MVP: `account_readiness`, `calendar_inbox`, `message_delivery` e `instagram_inbox`. Eles usam dados fortemente escopados por conta/inbox/conversa, tem baixo risco de regressao e entregam valor direto para suporte/operacao.

Depois, adicionar `webhook_delivery` e `queue_health` com linguagem honesta sobre incerteza: hoje eles conseguem apontar configuracao e estado de fila, mas nao conseguem reconstruir historico completo de entrega. `assignment_decision` e `automation_conflict` devem vir na segunda onda porque exigem inferencia e podem ser confundidos com uma explicacao historica se a UI/API nao deixar claro que e "decisao recalculada agora".

Infra minima que falta para um operador confiavel:

- `correlation_id` padrao em request -> dispatcher event -> job -> mensagem/webhook.
- Tabela `webhook_deliveries` com `account_id`, `webhook_id`, `event`, `delivery_id`, `status`, `http_status`, `attempt`, `next_retry_at`, `error_class`, `error_message` truncado e timestamps.
- Tabela leve de `diagnostic_runs` ou logs estruturados para auditar o que o agente consultou e respondeu.
- Convenção de `account_id` em todos os jobs operacionais ou um wrapper de metadata para ActiveJob.
- Mascaramento centralizado de telefone/token/email em evidence.
- API read-only nova sob namespace Autonomia/Operator, gated por ENV e Pundit, sem expor Sidekiq global para usuarios de conta.

Estimativa de MVP:

- 1 semana: `account_readiness`, `calendar_inbox`, `message_delivery`, `instagram_inbox`, formato comum de resposta e controller read-only.
- +1 semana: `webhook_delivery` readiness, `queue_health` restrito/admin, testes e hardening de mascaramento.
- +1 a 2 semanas: `assignment_decision` e `automation_conflict` com inferencia segura e mensagens de incerteza.

Conclusao: viabilidade alta. O repositorio ja tem sinais suficientes para diagnostico operacional util sem tocar fluxos de escrita. O maior risco nao e tecnico de leitura; e produto/seguranca: o agente precisa comunicar incerteza quando faltar historico persistido e precisa respeitar isolamento de conta ao consultar Redis/Sidekiq.
