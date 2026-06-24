# Probe 1 - API Surface / Endpoint Catalog / `call_operation`

Data da sonda: 2026-06-20. Escopo: pilar 1 do PRD de Agente Operacional Autonomo, contra o codigo real deste fork Chatwoot v4.15.1 EE white-label.

## Resumo executivo

O pilar e viavel como **catalogo versionado e curado de operacoes**, com descoberta (`platform.search_operations`) e execucao (`call_operation`) sobre uma allow-list. Nao e viavel com seguranca como "proxy generico para qualquer rota" neste estado do codigo.

Motivos principais:

- A superficie real sob `api/v1/accounts` tem ordem de grandeza de **~600 endpoints potenciais** por leitura estatica de `config/routes.rb:53-601`.
- O OpenAPI existente cobre bem menos: `swagger/swagger.json` tem **89 paths totais**, **57 paths de account API** e **99 operacoes** sob `/api/v1/accounts`; nao cobre os namespaces customizados principais (`crm`, `autonomia`, `campaign_imports`, `email_campaigns`).
- Os contratos de request vivem majoritariamente em strong params nos controllers; nao ha schema central versionado que um agente possa consumir com seguranca.
- A autorizacao Pundit existe e e ampla, mas nao e uniforme nem verificada globalmente por `verify_authorized`. Um catalogo permission-aware precisa de metadados explicitos por operacao.
- Ha muitos endpoints destrutivos, assincornos ou com efeito externo irreversivel: delete de contatos/conversas/inboxes, bulk actions, reset de segredo, webhooks com PII, campanhas e reunioes/calendarios.

Recomendacao: construir primeiro uma allow-list pequena, com metadata de risco, policy, schema, dry-run/confirmacao/undo quando aplicavel. Usar introspeccao de rotas apenas para validar drift em CI/build, nao para liberar chamadas automaticamente.

## Superficie de API

Evidencia principal: `config/routes.rb:51-601`.

O bloco account-scoped comeca em `config/routes.rb:53-55` e termina em `config/routes.rb:601`. Ele inclui o wrapper `resources :accounts` e, dentro dele, `scope module: :accounts`.

Contagem estatica feita sobre esse bloco:

| Medida | Valor |
| --- | ---: |
| Linhas no bloco account-scoped | 546 |
| Declaracoes `resources`/`resource` | 119 |
| Declaracoes plural `resources` | 90 |
| Declaracoes singular `resource` | 29 |
| Verbos explicitos no DSL (`get/post/patch/delete`) | 202 |
| `GET` explicitos | 67 |
| `POST` explicitos | 116 |
| `PATCH` explicitos | 7 |
| `DELETE` explicitos | 12 |
| Expansao REST aproximada, incluindo `accounts` | 399 |
| Total aproximado REST + verbos explicitos | 601 |

Observacoes sobre a contagem:

- `bundle exec rails routes` nao estava disponivel neste ambiente (`rbenv`/Bundler ausentes no shell), entao a contagem e estatica e aproximada.
- A expansao considera convencoes Rails: `update` conta como `PATCH` e `PUT`; recursos sem `only:` contam como REST completo.
- O numero e suficiente para decisao arquitetural: mesmo com erro de algumas dezenas, a ordem de grandeza e centenas de operacoes.

Namespaces customizados relevantes dentro do bloco:

- CRM: `config/routes.rb:154-244`, com pipelines, stages, cards, follow-ups, meetings, calendar, reports, integration tokens e bulk de cards.
- Autonomia agents/copilot: `config/routes.rb:245-269`.
- Email campaigns: `config/routes.rb:270-305`.
- Campaign imports: `config/routes.rb:147-153`.
- WhatsApp API campaigns: `config/routes.rb:140-145`.

Enterprise:

- Nao ha arquivo de rotas separado em `enterprise/` (`find enterprise -path '*routes*'` retornou vazio).
- Ha condicionais EE no proprio bloco account-scoped: **6 linhas** com `ChatwootApp.enterprise?` (`config/routes.rb:342`, `392`, `401`, `410`, `412`, `441`).
- Ha tambem namespace separado `/enterprise/api/v1/accounts` em `config/routes.rb:708-722`, com `resources :accounts` e membros `checkout`, `subscription`, `limits`, `toggle_deletion`, `topup_checkout`. Isso nao fica sob `/api/v1/accounts`, mas impacta qualquer estrategia global de catalogo.
- Controllers EE sob account API existem: **27 arquivos** em `enterprise/app/controllers/api/v1/accounts`.

Controllers account API:

- `app/controllers/api/v1/accounts`: **116 arquivos**.
- `enterprise/app/controllers/api/v1/accounts`: **27 arquivos**.
- Total combinado: **143 arquivos**.

## OpenAPI / Swagger / rswag

Existe OpenAPI estatico em `swagger/`.

Evidencias:

- `swagger/swagger.json` declara `openapi: 3.1.0`.
- `swagger/index.yml` e `swagger/paths/index.yml` montam os paths por `$ref`.
- `swagger/paths/application`: **107 arquivos**.
- `swagger/` inteiro: **294 arquivos**.
- `app/controllers/swagger_controller.rb` serve arquivos de `swagger/`, mas apenas em `development` ou `test`; em outros ambientes retorna `404`.
- `Gemfile:38` inclui `json_refs` "used in swagger build".
- Busca por `rswag` nao encontrou gem/config; nao ha rswag como fonte viva de contrato.

Cobertura comparada com as rotas reais:

| Medida em `swagger/swagger.json` | Valor |
| --- | ---: |
| Paths totais | 89 |
| Paths iniciando com `/api/v1/accounts` | 57 |
| Operacoes HTTP sob `/api/v1/accounts` | 99 |
| Paths contendo `autonomia` | 0 |
| Paths contendo `crm` | 0 |
| Paths contendo `campaign_imports` | 0 |
| Paths contendo `email_campaigns` | 0 |

Conclusao: o Swagger existente ajuda como referencia de alguns endpoints upstream (`inboxes`, `agents`, `automation_rule`, `webhooks`, `contacts`, `conversation`), mas nao pode ser a fonte de verdade do agente operacional neste fork.

## Contratos / strong params

Nao ha camada central de contratos por endpoint. O padrao atual e strong params nos controllers, com variacoes locais.

Contagens nos 143 controllers account API:

| Padrao | Arquivos |
| --- | ---: |
| `params.permit` / `.permit(...)` | 82 |
| `params.require(...)` | 40 |
| `parameter_set(...)` custom do CRM | 14 |
| `permit!` | 3 |

Exemplos:

- `app/controllers/api/v1/accounts/inboxes_controller.rb` define `permitted_params` e schema flexivel por tipo de canal (`channel: [:type, *channel_attributes]`).
- `app/controllers/api/v1/accounts/automation_rules_controller.rb` permite `conditions` e `actions` diretamente em `automation_rules_permit`.
- `app/controllers/api/v1/accounts/crm/base_controller.rb` introduz `parameter_set(root_key)`, permitindo payloads com raiz (`card`, `meeting`, etc.) ou sem raiz.
- `app/controllers/api/v1/accounts/contacts_controller.rb` e `app/controllers/api/v1/accounts/conversations_controller.rb` usam `params.permit!` em filtros.
- `app/controllers/api/v1/accounts/crm/ai_settings_controller.rb` usa `permit!` para subestruturas de criterios/handoff.

`json_schemer` existe, mas aparece em modelos/configuracoes (`app/models/concerns/json_schema_validator.rb`, `app/models/dashboard_app.rb`, `app/models/integrations/hook.rb`), nao como contrato padrao de API.

Implicacao para `call_operation`: introspeccao de rotas nao descobre contrato. Swagger tambem nao cobre a superficie custom. Cada operacao allow-listed precisa de schema proprio, mesmo que inicialmente derivado manualmente dos strong params.

## Permissoes e isolamento de conta

Base:

- `ApplicationController` inclui `Pundit::Authorization` e define `pundit_user` como hash com `user`, `account`, `account_user` (`app/controllers/application_controller.rb:1-25`).
- `Api::BaseController` autentica usuario ou token, tem `check_authorization(model = nil)` e `check_admin_authorization?` (`app/controllers/api/base_controller.rb`).
- `Api::V1::Accounts::BaseController` inclui `EnsureCurrentAccountHelper` e executa `before_action :current_account` (`app/controllers/api/v1/accounts/base_controller.rb`).
- `EnsureCurrentAccountHelper` resolve `Current.account` por `params[:account_id]`, valida conta ativa e acessibilidade por usuario, bot ou integration token (`app/controllers/concerns/ensure_current_account_helper.rb`).

Contagens:

| Medida | Valor |
| --- | ---: |
| Policy files totais | 73 |
| Policy files OSS (`app/policies`) | 45 |
| Policy files EE (`enterprise/app/policies`) | 28 |
| Classes `Scope` em policies | 17 |
| Controllers account API com `authorize`/`check_authorization` | 97 de 143 |
| Controllers account API com `policy_scope` | 19 de 143 |
| Controllers account API que referenciam `Current.account` | 121 de 143 |
| `after_action :verify_authorized` / `verify_policy_scoped` | 0 ocorrencias |

Padroes positivos:

- Muitos controllers buscam dados por `Current.account`, reduzindo risco de cross-account.
- Policies usam `account_user` e, em EE, permissoes granulares. Exemplo: `enterprise/app/policies/crm_permissions.rb` define `crm_permission?`.
- `RestrictIntegrationTokenToCrm` e um precedente forte para catalogo permission-aware: mapeia controller/action para scopes `crm_*` e aplica default deny para integration tokens (`app/controllers/concerns/restrict_integration_token_to_crm.rb`).
- CRM tem scopes mais finos para cards: `Crm::CardPolicy::Scope` usa `Crm::Cards::VisibleScopeQuery`; overlay EE exige `crm_view`, `crm_manage_cards`, `crm_move_cards`, `crm_manage_ai`.

Pontos de atencao:

- Nao existe enforcement global de Pundit por action; alguns endpoints dependem de escopo por `Current.account` e nao de `authorize`.
- Nem toda mutacao tem policy semantica dedicada. Exemplo: atribuir conversa passa por `ConversationPolicy#show?` no controller-base, nao por `assign?`.
- `check_authorization` infere policy por `controller_name.classify.constantize` quando nao recebe model; isso funciona para padroes simples, mas nao e metadado consumivel por catalogo.
- Alguns endpoints usam guards por ENV/feature flag fora da policy (`Crm::Config.enabled?`, `EmailCampaigns::Config.enabled?`, `CampaignImports::Config.enabled?`, `WhatsappApiCampaigns::Config.enabled?`).

## Padroes Autonomia e CRM existentes

Autonomia tem **49 arquivos** somando `app/controllers/api/v1/accounts/autonomia`, `app/models/autonomia` e `app/services/autonomia`.

Controllers Autonomia:

- **9 arquivos** em `app/controllers/api/v1/accounts/autonomia`.
- `Api::V1::Accounts::Autonomia::BaseController` herda de `Api::V1::Accounts::BaseController`, aplica `ensure_feature_enabled` e `ensure_account_administrator`, e expoe scopes por `Current.account` (`app/controllers/api/v1/accounts/autonomia/base_controller.rb`).
- `ConversationCopilotController` deliberadamente nao herda do base admin-only; ele aplica gate `Crm::Config.enabled? && CRM_COPILOT_ENABLED` e autoriza a conversa com `authorize @conversation, :show?` (`app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:59-72`).
- `AgentsController` usa `agents_scope` account-scoped e strong params que evitam expor/escrever `scaffold` por params (`app/controllers/api/v1/accounts/autonomia/agents_controller.rb`).

CRM:

- `app/controllers/api/v1/accounts/crm/base_controller.rb` aplica `ensure_crm_enabled`.
- `Crm::Conversations::AccessAuthorizer` existe em `app/services/crm/conversations/access_authorizer.rb`.
- Ele e usado em `app/controllers/api/v1/accounts/crm/cards_controller.rb` e `app/controllers/api/v1/accounts/crm/follow_ups_controller.rb` para validar visibilidade de conversas alem do Pundit puro.
- `Crm::Conversations::Visibility` considera conta, usuario, `account_user`, inboxes do usuario e configuracao `assigned_only`.

Esses padroes sao bons precedentes para o agente operacional: operacoes devem receber contexto explicito (`account`, `user`, `account_user`), ter gate por feature flag e resolver permissao no nivel do objeto quando necessario.

## Viabilidade do catalogo versionado

### Geracao

Opcoes avaliadas:

1. Introspeccao de rotas Rails em runtime/build (`Rails.application.routes.routes`).
   - Boa para descobrir metodo/path/controller/action e detectar drift.
   - Ruim para contrato, risco, policy, feature flag, reversibilidade e semantica.

2. Swagger/OpenAPI existente.
   - Bom para alguns endpoints upstream.
   - Insuficiente neste fork: nao cobre `crm`, `autonomia`, `campaign_imports`, `email_campaigns`; servido apenas dev/test; nao e rswag/vivo.

3. Anotacoes/catalogo YAML/Ruby curado.
   - Melhor ajuste para este repo.
   - Pode referenciar controller/action e policy, mas precisa declarar metadados que hoje nao existem: schema, risco, idempotencia, undo, feature gates, redacao de auditoria, exemplos.

Recomendacao tecnica: catalogo versionado como artefato de codigo, por exemplo `config/operator_operations/*.yml` ou classes pequenas, gerado/validado no build da imagem. A introspeccao de rotas deve ser usada por um linter para garantir que cada operacao allow-listed ainda existe depois de updates Chatwoot.

Como producao nao tem checkout git, o catalogo deve ir dentro da imagem Docker. Versionar com:

- `catalog_version`.
- versao da aplicacao/imagem.
- checksum do arquivo de rotas ou snapshot dos route keys allow-listed.
- feature flag global, por exemplo `OPERATOR_AGENT_ENABLED=false` por default.

### Descoberta (`platform.search_operations`)

Nao deve retornar "todas as rotas". Deve buscar somente em operacoes publicadas no catalogo.

Cada item deveria conter no minimo:

- `operation_id` estavel e versionado.
- titulo/descricao em linguagem natural.
- metodo/path apenas como detalhe tecnico.
- `risk_level`: `read`, `low_write`, `medium_write`, `high_write`, `external_side_effect`.
- `required_policy`: classe/alvo/action.
- `feature_gates`: ENV/config/feature account.
- `params_schema` e exemplos seguros.
- `requires_confirmation`.
- `supports_dry_run`.
- `undo_operation_id` quando existir.
- `audit_redaction` para PII/secrets.

`platform.search_operations` deve ser permission-aware:

- Primeiro filtra por feature gates (`Crm::Config.enabled?`, `CampaignImports::Config.enabled?`, etc.).
- Depois avalia permissao de nivel de classe quando possivel (`InboxPolicy#create?`, `WebhookPolicy#create?`, etc.).
- Para operacoes em objeto, pode retornar a operacao mas marcar que a permissao final depende do alvo, ou exigir parametros suficientes para checar com `authorize record, :action?`.

### Execucao (`call_operation`)

`call_operation` nao deve fazer HTTP arbitrario nem aceitar path/method livres. Deve despachar por `operation_id` para um executor allow-listed que:

1. valida schema;
2. resolve conta/usuario por `Current`;
3. aplica feature gate;
4. resolve objetos por `Current.account`;
5. chama `authorize`/authorizer especifico;
6. aplica confirmacao para escrita de risco;
7. executa service/controller wrapper;
8. grava auditoria com payload redigido;
9. retorna envelope estavel.

Para endpoints existentes, reaproveitar service objects e policies e preferir wrappers finos a chamar controllers internamente. Onde hoje so existe logica dentro do controller, a allow-list inicial deve ser seletiva.

## Drift vs upstream

Risco alto se o catalogo for gerado automaticamente e publicado sem curadoria:

- O fork adicionou muitos namespaces customizados no mesmo `config/routes.rb`.
- Enterprise usa `prepend_mod_with`/overlays e condicionais `ChatwootApp.enterprise?`.
- Swagger e manual e menor que a superficie real.
- Strong params mudam junto com controllers.
- Alguns endpoints sao legados/deprecated, ex.: comentario em `InboxesController#assignable_agents`.

Mitigacoes:

- Linter de catalogo em CI/build: para cada `operation_id`, confirmar que route/controller/action existem.
- Teste de permissao por operacao allow-listed.
- Snapshot do catalogo gerado na imagem; nao depender de busca em git em producao.
- Renovar catalogo por PR junto com mudancas de rota/contract.
- Marcar operacoes custom Autonomia/CRM como de propriedade local, separadas de upstream Chatwoot.

## Seguranca de escrita

Exemplos reais de endpoints/acoes destrutivas ou irreversiveis:

- `DELETE /api/v1/accounts/:account_id/contacts/:id`: `ContactPolicy#destroy?` exige admin, mas remove contato; bulk delete chama `Contacts::BulkDeleteService` com `destroy!`.
- `POST /api/v1/accounts/:account_id/bulk_actions`: pode deletar contatos (`Contacts::BulkActionService`) ou alterar conversas em lote (`BulkActionsJob`).
- `DELETE /api/v1/accounts/:account_id/conversations/:id`: `ConversationsController#destroy` chama `Conversations::DeleteService`, que enfileira `DeleteObjectJob` e registra mensagens de email deletadas.
- `DELETE /api/v1/accounts/:account_id/inboxes/:id`: `InboxesController#destroy` enfileira `DeleteObjectJob`.
- `POST /api/v1/accounts/:account_id/inboxes/:id/reset_secret`: `InboxesController#reset_secret` chama `@inbox.channel.reset_secret!`; nao ha undo.
- `POST /api/v1/accounts/:account_id/email_campaigns/campaigns/:id/send_now`: envia campanha; efeito externo irreversivel.
- `POST /api/v1/accounts/:account_id/whatsapp_api_campaigns/:id/cancel`: cancelamento pode ser correto, mas altera fila/campanha em andamento.
- `DELETE /api/v1/accounts/:account_id/crm/meetings/:id`: `MeetingsController#destroy` chama `Crm::Meetings::CancelService` e pode cancelar evento externo de calendario via services Google/Microsoft.
- `DELETE /api/v1/accounts/:account_id/portals/:portal_id/articles/bulk_actions/delete_articles`: delete em lote de artigos.
- `POST/PATCH /api/v1/accounts/:account_id/webhooks`: pode configurar exfiltracao futura, inclusive `include_contact_pii`.

Exemplos de acoes mais reversiveis:

- Atribuir conversa a outro agente/time: nova escrita pode reverter o estado, se o estado anterior foi capturado.
- Adicionar/remover labels de conversa/contato: reversivel se registrar delta anterior.
- CRM card bulk "delete" arquiva (`status: archived`) em `Crm::Cards::BulkAction`, explicitamente comentado como soft-delete reversivel.
- `campaign_imports#undo_labels` foi desenhado como undo explicito para remover labels aplicadas por import.

Requisitos minimos antes de qualquer escrita por agente:

- Confirmacao humana para `medium_write` ou superior.
- Dry-run quando a operacao tocar multiplos registros.
- Idempotency key para execucoes com efeito externo ou assincorno.
- Snapshot de antes/depois para operacoes reversiveis.
- Bloqueio default para deletes fisicos, reset de segredo, envio de campanha, webhooks com PII e operacoes de integracao externa ate haver UX/processo especifico.
- Auditoria com redacao de telefone, email, tokens, URLs sensiveis e payload de webhook.

## 5 endpoints de alto valor

| Operacao | Rota real | Controller/acao | Policy/autorizacao | Reversibilidade | Observacao para catalogo |
| --- | --- | --- | --- | --- | --- |
| Criar inbox | `POST /api/v1/accounts/:account_id/inboxes` (`config/routes.rb:428`) | `Api::V1::Accounts::InboxesController#create` | `InboxPolicy#create?` exige admin; `before_action :check_authorization`; `validate_limit` | Parcial. Pode deletar depois, mas delete e assincorno e canal externo pode ter efeitos fora do Rails. | Alto valor, mas precisa schema por tipo de canal e confirmacao. Comecar talvez apenas com `channel.type=api` ou leitura/listagem. |
| Criar automacao | `POST /api/v1/accounts/:account_id/automation_rules` (`config/routes.rb:125`) | `AutomationRulesController#create` | `AutomationRulePolicy#create?` exige admin | Parcial. Pode desativar/deletar, mas uma automacao ativa pode disparar mensagens/webhooks irreversiveis. | Exigir dry-run/preview de regra e criar como `active=false` por default no agente. |
| Atribuir conversa | `POST /api/v1/accounts/:account_id/conversations/:conversation_id/assignments` (`config/routes.rb:324`) | `Conversations::AssignmentsController#create` | `Conversations::BaseController` resolve `Current.account.conversations` e `authorize @conversation, :show?`; nao ha `assign?` dedicado | Boa se capturar estado anterior; reatribuir/desatribuir corrige. | Bom candidato inicial, mas catalogo deve declarar que permissao efetiva e "pode ver conversa", nao admin. |
| Mudar permissao/role de agente | `PATCH /api/v1/accounts/:account_id/agents/:id` (`config/routes.rb:69`) | `AgentsController#update` atualiza `@agent.current_account_user` (`role`, `availability`, `auto_offline`) | `UserPolicy#update?` exige admin via `check_authorization(User)` | Parcial. Role anterior pode ser restaurada; remocoes/deletes nao. | Alto risco administrativo. Exigir confirmacao forte e registrar role anterior. |
| Criar/alterar webhook | `POST /api/v1/accounts/:account_id/webhooks` e `PATCH /api/v1/accounts/:account_id/webhooks/:id` (`config/routes.rb:532`) | `WebhooksController#create/update` | `WebhookPolicy#create?/update?` exige admin | Parcial. Pode remover webhook, mas eventos ja enviados e PII vazada nao voltam. | Bloquear por default no `call_operation` inicial; liberar depois com allow-list de dominios e confirmacao. |

## Veredito de viabilidade

Viabilidade do pilar:

- **Catalogo versionado + search permission-aware:** viavel.
- **`call_operation` sobre allow-list curada:** viavel.
- **`call_operation` generico sobre toda a API:** nao recomendado; risco alto de dano operacional, vazamento e drift.

Esforco T-shirt:

- **M**: catalogo curado read-only + `platform.search_operations` + verificacao de feature/policy por classe para 10-20 operacoes.
- **L**: `call_operation` allow-listed com schemas, auditoria, confirmacao, alguns writes de baixo/medio risco e testes.
- **XL/XXL**: catalogo generico cobrindo centenas de endpoints com schemas, object-level authorization, undo/dry-run e compatibilidade upstream/EE. Nao recomendo como primeira fase.

Top riscos:

1. **Drift de rota/contrato** entre upstream Chatwoot, EE overlays e custom local.
2. **Permissao incompleta** se o catalogo inferir policy por nome em vez de declarar alvo/action.
3. **Writes irreversiveis**: deletes, reset de segredo, envio de campanha, webhooks e integracoes externas.
4. **Prompt injection operacional**: usuario final ou texto de conversa induzindo o agente a chamar operacoes destrutivas.
5. **Cross-account leakage** se qualquer resolver usar busca global em vez de `Current.account`.
6. **PII/secrets em logs/auditoria** se `call_operation` registrar payload bruto.

Recomendacao final:

Comecar com allow-list curada, nao catalogo generico. A primeira entrega deveria conter:

- `OPERATOR_AGENT_ENABLED=false` por default.
- `platform.search_operations` buscando somente operacoes allow-listed.
- Catalogo versionado em codigo, com linter contra rotas reais no build.
- `call_operation(operation_id, params, confirmation_token: nil)` sem path/method livre.
- Apenas leitura/diagnostico e poucos writes reversiveis: listar inboxes/agentes/labels, buscar conversa, atribuir conversa, adicionar/remover label, talvez atualizar prioridade/status com snapshot.
- Bloquear inicialmente delete, bulk delete, reset secret, webhook create/update, envio/cancelamento de campanha e mudancas de permissao de usuario.

Depois que o modelo de auditoria, confirmacao, schema e permission checks estiver provado, expandir por dominios: CRM cards, campaign imports, inbox administration, automations. O catalogo pode crescer, mas sempre por operacao declarada e testada.
