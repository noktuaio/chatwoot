# Probe 5 - Seguranca / escopo / autonomia + inventario de reuso

Data da sondagem: 2026-06-20.

Escopo: avaliar o pilar de seguranca, escopo, autonomia e reuso para um "Agente Operacional Autonomo" contra o codigo real deste fork Chatwoot v4.15.1 EE white-label. Este documento nao implementa nada.

Premissa importante: nao encontrei no repo um PRD versionado com secoes `EP-01` a `EP-12` nem ocorrencia do termo `cal39`. A tabela de inventario usa a numeracao pedida como eixos funcionais inferidos a partir do pedido, e evidencia o codigo existente quando ha reuso concreto.

## Resumo executivo

O projeto tem uma base boa para leitura assistida: `Current`, Pundit, `policy_scope`, gates por ENV/conta, credenciais OpenAI por conta, runtime Autonomia Agents/RAG e um copiloto de conversa que ja trata transcricao como dado nao confiavel. Isso permite um agente operacional de diagnostico/leitura com risco controlavel.

Para escritas amplas, o veredito e bloqueante: o modelo de seguranca precisa vir antes. O codigo atual tem muitos endpoints destrutivos ou parcialmente destrutivos, varios com `destroy!`, `destroy_all`, `delete_all`, cascatas async e efeitos externos. Um undo generico "before/after" nao e viavel hoje porque os endpoints normalmente nao devolvem estado anterior completo, os destroys apagam grafos de dados/arquivos e algumas operacoes disparam compromissos externos.

Recomendacao: iniciar o pilar como uma camada backend de `OperatorAgent::ActionRegistry` + `CapabilityEnvelope`, default deny, com dry-run, classificacao de risco, confirmacao obrigatoria para alto risco, backup/snapshot por dominio antes de destrutivo, auditoria forte e execucao sempre via `Current`/Pundit/policy scopes. O modelo nunca deve confiar no papel ou escopo que o LLM alegar.

## Contagens reais desta arvore

Contagens feitas com `rg`/`find` no working dir atual.

| Item | Contagem | Observacao |
| --- | ---: | --- |
| Arquivos de policy em `app/policies` + `enterprise/app/policies` | 73 | Base real de Pundit/EE a respeitar. |
| Arquivos com `autonomia`/`Autonomia` em `app`, `config`, `enterprise`, `spec` | 107 | Inclui backend, frontend, rotas e configuracoes. |
| Services Ruby em `app/services/autonomia` | 34 | Runtime Autonomia Agents/Copilot/Builder/Operate. |
| Models Ruby em `app/models/autonomia` | 6 | Agents, sources, knowledge, threads, inbox bindings. |
| Controllers Ruby em `app/controllers/api/v1/accounts/autonomia` | 9 | Endpoints admin de agentes e copiloto agent-facing. |
| Jobs Ruby em `app/jobs/autonomia` | 7 | Ingestao/build/reply/recompute. |
| Arquivos frontend Autonomia em `app/javascript/dashboard` | 39 | Rotas, paginas, widget, store e APIs. |
| API clients frontend Autonomia | 7 | Inclui `autonomiaCopilot`. |
| `def destroy` em controllers `app/controllers` + `enterprise/app/controllers` | 81 | Superficie destrutiva ampla. |
| Chamadas `.destroy!` em `app` + `enterprise` | 63 | Varias com cascata/dependencias. |
| Chamadas `.destroy_all` em `app` + `enterprise` | 28 | Algumas em bulk/EE. |
| Chamadas `.delete_all` em `app` + `enterprise` | 14 | Bypass de callbacks; ruim para undo generico. |
| Linhas `delete`/`destroy` em `config/routes.rb` | 91 | Rotas DELETE/destrutivas registradas. |
| Ocorrencias `bulk`/`Bulk` em controllers/services/jobs | 69 | Ha superficie de lote relevante para confirmacao. |

## 1. Isolamento de conta

O fluxo base e bom e ja esta alinhado com Pundit:

- `app/controllers/application_controller.rb:4` inclui `Pundit::Authorization`.
- `app/controllers/application_controller.rb:10` registra `before_action :set_current_user`.
- `app/controllers/application_controller.rb:16-19` seta `Current.user = current_user`.
- `app/controllers/application_controller.rb:21-27` passa para Pundit um hash com `Current.user`, `Current.account` e `Current.account_user`.
- `lib/current.rb:1-16` mantem os atributos thread-local usados por controllers/services.

Conta corrente e membership sao resolvidas em `Api::V1::Accounts::BaseController` via `EnsureCurrentAccountHelper`:

- `app/controllers/concerns/ensure_current_account_helper.rb:4-7` seta `Current.account`.
- `app/controllers/concerns/ensure_current_account_helper.rb:9-20` busca `Account.find(params[:account_id])`, valida conta ativa e escolhe o caminho de autenticacao.
- `app/controllers/concerns/ensure_current_account_helper.rb:23-27` seta `Current.account_user` a partir de `account.account_users.find_by(user_id: current_user.id)`.
- `app/controllers/concerns/ensure_current_account_helper.rb:42-45` bloqueia token de integracao usado fora da conta do token.

Pundit recebe esse contexto em `app/policies/application_policy.rb:4-10`. O default e negar `index?`, `create?`, `update?` e `destroy?` (`app/policies/application_policy.rb:12-38`), e `show?` usa `scope.exists?(id: record.id)` (`app/policies/application_policy.rb:16-18`). A classe `Scope` carrega `account` e `account_user` (`app/policies/application_policy.rb:44-57`).

### Padroes Autonomia existentes

Os controllers admin de Autonomia seguem um padrao mais restrito que o core:

- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:1-3` herda de `Api::V1::Accounts::BaseController` e roda `ensure_feature_enabled` + `ensure_account_administrator`.
- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:7-11` devolve 404 quando `Autonomia::Agents::Config.enabled?(Current.account)` esta desligado.
- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:13-17` exige `Current.account_user&.administrator?`.
- `app/controllers/api/v1/accounts/autonomia/base_controller.rb:19-26` define scopes presos a `Current.account` para agentes e build threads.

O copiloto de conversa e intencionalmente diferente: nao e admin-only, mas e conta/conversa-scoped e passa por policy:

- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:1-5` documenta que qualquer agente que possa ver a conversa pode usar.
- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:59-65` aplica gate por `Crm::Config.enabled?` + `CRM_COPILOT_ENABLED`.
- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:70-72` busca a conversa em `Current.account.conversations` por `display_id` e chama `authorize @conversation, :show?`.
- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb:21-36` lista apenas agentes `internal`/`both`, ativos, da conta, sem vazar instruction/scaffold/config.

CRM tambem tem scopes especificos que devem ser preservados pelo agente operacional:

- `app/services/crm/conversations/access_authorizer.rb:8-12` encapsula autorizacao de visibilidade e levanta `Pundit::NotAuthorizedError`.
- `app/services/crm/conversations/visibility.rb:17-24` valida mesma conta, admin ou acesso de inbox.
- `app/services/crm/conversations/visibility.rb:30-39` exige assignee/participante quando a inbox e assigned-only.
- `app/services/crm/cards/visible_scope_query.rb:9-15` limita cards a conta corrente, admin ou visibilidade do agente.
- `app/services/crm/cards/visible_scope_query.rb:19-47` diferencia inboxes visiveis, assigned-only e cards standalone do proprio dono.

Conclusao: isolamento de conta existe, mas um agente operacional de escrita nao pode acessar models diretamente. Todo finder de ferramenta precisa partir de `Current.account`, `policy_scope` ou services de visibilidade equivalentes.

## 2. Envelope de papel/escopo

### O que existe

Papels base:

- `app/models/account_user.rb:36` define `role` como `agent` ou `administrator`.
- `app/models/account_user.rb:63-65` expoe permissoes simples: `['administrator']` ou `['agent']`.
- `enterprise/app/models/enterprise/account_user.rb:1-4` substitui isso por `custom_role.permissions + ['custom_role']` quando ha custom role.

Custom roles EE:

- `enterprise/app/models/custom_role.rb:19-32` documenta permissoes granulares.
- `enterprise/app/models/custom_role.rb:38-52` define 12 permissoes: conversas, contatos, reports, knowledge base e CRM (`crm_view`, `crm_manage_cards`, `crm_move_cards`, `crm_manage_pipelines`, `crm_manage_ai`, `crm_view_reports`, `crm_admin`).

Exemplos de diferenca de capacidade:

- `app/policies/contact_policy.rb:10-16` restringe import/export a admin no core.
- `enterprise/app/policies/enterprise/contact_policy.rb:1-8` libera import/export para custom role com `contact_manage`.
- `app/policies/contact_policy.rb:26-44` permite update/show/create para qualquer membro autorizado da conta, o que e amplo demais para um agente operacional automatico.
- `enterprise/app/policies/crm_permissions.rb:9-19` permite CRM para admin, para custom roles com permissao especifica, e tambem para agentes sem custom role.

O ponto critico esta em `enterprise/app/policies/crm_permissions.rb:3-7`: por decisao de compatibilidade, agente comum sem custom role mantem acesso CRM cheio. Portanto, "o usuario e agente" nao e envelope suficiente para ferramenta de escrita automatica.

Tambem existe um padrao de escopo por token muito relevante:

- `app/controllers/concerns/restrict_integration_token_to_crm.rb:1-9` declara o gate fail-closed.
- `app/controllers/concerns/restrict_integration_token_to_crm.rb:19-76` mapeia controller/action para escopos `crm_*`.
- `app/controllers/concerns/restrict_integration_token_to_crm.rb:80-90` nega controller/action fora do mapa e exige `crm_admin` ou o escopo explicito.

Esse e o melhor padrao existente para um capability envelope: mapa explicito, default deny, backend-calculated.

### O que falta

Nao existe uma camada backend que:

- receba uma acao proposta pelo modelo e valide contra um registro de ferramentas permitido;
- classifique risco por acao;
- aplique limites de lote;
- force dry-run/confirmacao;
- capture snapshot/backup antes de destrutivo;
- escolha estrategia de undo por dominio;
- audite a acao como "operador agente" separada de clique humano normal.

### Como impor sem confiar no modelo

O envelope deve ser calculado no backend, a partir de `Current.user`, `Current.account`, `Current.account_user`, flags do servidor e policies. O LLM pode propor `tool_name` e argumentos; nao pode declarar "sou admin", "tenho crm_admin", "pode deletar", "foi confirmado" ou "isso e reversivel".

Modelo recomendado:

- `OperatorAgent::CapabilityEnvelope` monta capacidades do ator corrente.
- `OperatorAgent::ActionRegistry` lista acoes permitidas, cada uma com policy, scope resolver, schema de parametros, limite de afetados, nivel de risco, necessidade de confirmacao, necessidade de backup, estrategia de undo e flag de efeito externo.
- Todo lookup de record usa `policy_scope` ou scopes existentes (`Current.account.contacts`, `Crm::Cards::VisibleScopeQuery`, `Crm::Conversations::AccessAuthorizer`).
- Acoes nao registradas sao negadas como em `RestrictIntegrationTokenToCrm`.
- Pundit continua sendo baseline, mas o envelope e mais restritivo que Pundit para automacao.

Exemplo de niveis:

| Nivel | Classe | Execucao automatica |
| --- | --- | --- |
| R0 | Leitura/diagnostico sem export sensivel | Permitida com Pundit/scope. |
| R1 | Escrita unica, reversivel, baixo impacto | Pode ser permitida em modo assistido, com dry-run e auditoria. |
| R2 | Lote ou muitos registros | Exige confirmacao humana explicita e limite backend. |
| R3 | Destrutivo/perda de dados/configuracao/seguranca/export | Exige confirmacao, backup/snapshot e trilha de auditoria. |
| R4 | Compromisso externo: envio, agenda, webhook, notificacao | Exige confirmacao explicita; undo nao prometido. |

## 3. Seguranca de escrita e undo

### Escritas relativamente reversiveis

Estas operacoes parecem recuperaveis se uma ferramenta capturar o estado anterior antes de executar:

- CRM card archive: `app/controllers/api/v1/accounts/crm/cards_controller.rb:109-114` muda `status` para `archived` e renderiza o card. Reversao exigiria guardar status/campos anteriores.
- CRM bulk card: `app/services/crm/cards/bulk_action.rb:20-22` define delete como soft-delete/archived, com limite `MAX_IDS = 100`.
- CRM bulk usa escopo visivel: `app/services/crm/cards/bulk_action.rb:121-130` reutiliza `Crm::Cards::VisibleScopeQuery`.
- Move/close de card: `app/controllers/api/v1/accounts/crm/cards_controller.rb:116-139` usa idempotencia e services, mas undo exige guardar stage/status/owner/valor/lost_reason anteriores.
- Campaign import labels: `app/services/campaign_imports/undo_labels.rb:11-24` remove apenas labels aplicadas por aquela importacao e atualiza status. Este e um bom exemplo de undo por dominio, nao generico.
- `app/controllers/api/v1/accounts/campaign_imports_controller.rb:72-97` so enfileira undo de labels quando a importacao esta completa ou completa com falhas.

### Escritas destrutivas ou nao genericamente reversiveis

Exemplos reais:

- Contato individual: `app/controllers/api/v1/accounts/contacts_controller.rb:100-109` chama `@contact.destroy!`.
- Contatos em lote: `app/services/contacts/bulk_action_service.rb:8-15` encaminha `action_name == 'delete'` para delete; `app/services/contacts/bulk_delete_service.rb:7-10` faz `contacts.find_each(&:destroy!)`.
- Objetos grandes: `app/jobs/delete_object_job.rb:6-11` purga associacoes pesadas e chama `object.destroy!`.
- Account/Inbox purge: `app/jobs/delete_object_job.rb:18-39` faz batch destroy de conversas, contatos, inboxes e reporting events antes do destroy final.
- Email campaign delete: `app/controllers/api/v1/accounts/email_campaigns/campaigns_controller.rb:29-35` usa `EmailEvent.where(...).delete_all`, `email_campaign_recipients.delete_all` e `@campaign.destroy!`.
- Autonomia agents: `app/controllers/api/v1/accounts/autonomia/agents_controller.rb:37-39` destroi agente; o model tem dependencias de fontes, conhecimento, build threads, inbox bindings e eventos.
- Autonomia sources: `app/controllers/api/v1/accounts/autonomia/agents/sources_controller.rb:31-35` destroi fonte e agenda recomputo; `app/models/autonomia/agents/source.rb` usa `dependent: :delete_all` para knowledge entries.
- Calendario externo: `app/services/crm/meetings/cancel_service.rb:57-63` chama Google/Microsoft `delete_event`; depois `app/services/crm/meetings/cancel_service.rb:22-23` marca localmente como cancelado e cancela reminder.
- Campanhas de email/WhatsApp: send/cancel/pause/resume tem efeito operacional e externo; "undo" depois de envio nao e real.

### Viabilidade de undo generico

Undo generico por before/after nao e viavel com a arquitetura atual:

- muitos endpoints retornam apenas o estado final ou `head :ok/no_content`, nao o estado anterior;
- deletes usam cascata ActiveRecord, `destroy_async`, `delete_all` e jobs;
- `delete_all` bypassa callbacks e impede reconstruir efeitos colaterais por eventos de dominio;
- anexos/arquivos podem ser purgados;
- auditoria EE existente e parcial e pos-fato, nao snapshot completo de grafo;
- efeitos externos, como calendario e campanhas, nao podem ser "desenviados";
- bulk parcial pode deixar parte dos registros alterada e parte falha.

O caminho seguro e undo por acao/dominio: cada ferramenta declara se e reversivel, qual snapshot minimo precisa, e qual comando de compensacao existe. Destrutivo sem estrategia de restore deve exigir backup externo e confirmacao.

## 4. Autonomia ampla vs regras duras do dono

Ha conflito direto entre "agir por padrao" e as regras duras:

- exclusao/perda de dados nao pode ser automatica;
- lote amplo nao pode ser automatico;
- compromisso externo nao pode ser automatico;
- destrutivo exige backup antes;
- nao regressao exige kill switch e rollout por conta;
- o modelo nao pode decidir sozinho que uma acao e segura.

Modelo conservador-primeiro recomendado:

1. Default read-only: diagnosticar, explicar, navegar, sugerir proximas acoes e montar plano.
2. Escrita R1: somente acoes registradas, single-record, baixo impacto, reversiveis, com dry-run e auditoria.
3. Escrita R2: lote limitado, sempre com contagem de afetados e confirmacao.
4. R3/R4: destruicao, export, seguranca, configuracoes, credenciais, campanhas, agenda externa e qualquer perda de dados exigem confirmacao explicita e, quando aplicavel, snapshot/backup.
5. Modo admin nao remove confirmacao de R3/R4; apenas habilita o usuario a confirmar.
6. O backend deve recusar acao quando a confirmacao nao bate exatamente com a proposta validada: mesma conta, mesmo ator, mesmos parametros, mesmo hash de plano e dentro de janela curta.
7. Todo plano executavel deve mostrar impacto: tipo de acao, registros afetados, risco, reversibilidade, backup, efeito externo e politica usada.

## 5. Inventario de reuso contra EP-01..EP-12

Como nao ha PRD com os nomes dos epicos nesta arvore, os titulos abaixo sao eixos inferidos do pedido.

| Epico | Estado | Reuso real | Falta / risco |
| --- | --- | --- | --- |
| EP-01 - Rollout, flags e kill switch | Parcial | Padrao maduro em `DashboardController#app_config` (`app/controllers/dashboard_controller.rb:80-87`), `Autonomia::Agents::Config.enabled?` (`app/services/autonomia/agents/config.rb:135-155`) e gate por conta (`app/services/autonomia/agents/config.rb:157-200`). | Falta `OPERATOR_AGENT_ENABLED`, opt-in por conta e modo de autonomia por conta/usuario. |
| EP-02 - Identidade, conta e Pundit | Parcial forte | `Current.user/account/account_user`, Pundit hash, `policy_scope`, Autonomia base admin-only e copiloto com `authorize :show?`. | Falta identidade/auditoria propria de "acao executada pelo agente operacional em nome de X" e envelope mais restritivo que roles. |
| EP-03 - LLM runtime e credenciais | Pronto para leitura/geracao | `Crm::Ai::CredentialResolver` resolve credencial por conta/sistema; `Crm::Ai::ResponsesClient` usa `store:false` no fluxo normal (`app/services/crm/ai/responses_client.rb:28-33`) e valida `api_base` contra SSRF (`app/services/crm/ai/responses_client.rb:116-168`). | Falta suporte formal a tool calls operacionais com validacao server-side e idempotencia. |
| EP-04 - Chat natural assistivo | Parcial | `Autonomia::Copilot::ConversationChat` existe (`app/services/autonomia/copilot/conversation_chat.rb`) e o widget e montado em `app/javascript/dashboard/routes/dashboard/Dashboard.vue:34-36` e `:175-182`. | Hoje e preso a conversa; falta assistente global de plataforma, roteamento de intencao e historico operacional. |
| EP-05 - RAG/knowledge de agentes | Parcial | Runtime Autonomia Agents tem 34 services, 6 models e jobs de ingest/build/recompute. `ConversationChat` reutiliza agentes `internal`/`both` e trata transcricao como dado nao confiavel (`app/services/autonomia/copilot/conversation_chat.rb:17-19`, `:60-78`). | Falta knowledge base da propria plataforma: mapa de rotas, policies, docs internas, capacidade de acao e manuais. |
| EP-06 - Descobrir e navegar a plataforma | Falta/parcial | Rotas frontend/backend existem, sidebar/command bar existem, e o copiloto pode orientar dentro de conversa. | Nao ha inventario semantico de telas, permissoes, controllers e workflows para navegacao NL global. |
| EP-07 - Diagnostico operacional read-only | Parcial | Existem services de visibilidade CRM, analytics Autonomia e muitos endpoints index/show. | Falta camada unificada de ferramentas read-only com scopes, redacao de PII e respostas com citacao de registros. |
| EP-08 - Execucao de ferramentas/acoes | Falta | O codigo tem services de dominio reaproveitaveis, como movers/closers, bulk CRM e import undo. | Nao ha action runner/operator tool registry. Usar controllers diretamente pelo LLM seria inseguro. |
| EP-09 - Capability envelope, aprovacao e risco | Falta com padrao reutilizavel | `RestrictIntegrationTokenToCrm` e um bom exemplo de mapa default-deny por controller/action (`app/controllers/concerns/restrict_integration_token_to_crm.rb:19-90`). | Falta registro por ferramenta com risco, confirmacao, limite de lote, backup, undo e efeito externo. |
| EP-10 - Undo, backup e auditoria | Parcial | Campaign import tem undo especifico; CRM cards arquivam em vez de hard delete; `Crm::ActivityLogger` registra atividades. | Undo generico nao e viavel. Falta snapshot/backup por dominio, auditoria de agente e restore testado. |
| EP-11 - Efeitos externos: email, WhatsApp, calendario | Parcial | Services de campanhas e calendario existem; cancelamento de meeting e idempotente localmente e propaga a provider quando aplicavel. | Sao R4: precisam confirmacao explicita, simulacao/dry-run e mensagens de irreversibilidade. |
| EP-12 - Dev/deploy/observabilidade e LLM de dev | Parcial | `AGENTS.md` define workflow Codex/worktree; `ResponsesClient` loga modelo/tools/latencia sem prompt/conteudo (`app/services/crm/ai/responses_client.rb:209-218`). | Codex/LLM-de-dev e processo de engenharia, nao runtime de producao. Como producao roda imagem Docker Swarm sem checkout git, o agente operacional deve operar via produto/API versionada, nao por edicao ao vivo. Falta dashboard de seguranca/custo/execucoes. |

## 6. Modelo de seguranca que deve preceder qualquer escrita ampla

Antes de permitir escrita ampla, o minimo seguro e:

1. Flag global e por conta: `OPERATOR_AGENT_ENABLED=false` por default; opt-in por conta em atributo interno, seguindo `Autonomia::Agents::Config`.
2. Modos de autonomia: `read_only`, `assist_low_risk`, `confirmed_writes`; nunca "full auto" para R3/R4.
3. Registry default-deny: toda ferramenta registrada com policy, scope, schema, risco, maximo de afetados, confirmacao, backup, undo e auditoria.
4. Dry-run obrigatorio para qualquer escrita: retorna plano assinado/hash com registros afetados e risco.
5. Confirmacao server-side: confirmacao referencia o hash do plano, nao texto livre do modelo.
6. Backup/snapshot por dominio antes de destrutivo: sem snapshot validado, bloquear R3.
7. Auditoria propria: ator humano, conta, action id, parametros normalizados/redigidos, registros afetados, resultado, modelo, tools usadas, request id e confirmacao.
8. Idempotencia: toda ferramenta de escrita deve aceitar idempotency key.
9. Limites: lote maximo por ferramenta, rate limit, timeout e circuit breaker por conta.
10. PII/redacao: nao logar conteudo sensivel; seguir o padrao do `ResponsesClient` de metadados sem prompt/conteudo.

## Esforco estimado

Estimativa conservadora, sem contar produto/design detalhado:

- Fase 0 - design tecnico e provas de seguranca do envelope: 1 a 2 semanas.
- Fase 1 - agente read-only global com reuso de LLM/credential/gates e ferramentas diagnosticas escopadas: 3 a 5 semanas.
- Fase 2 - action registry + dry-run + auditoria + confirmacao + primeiras escritas R1 em CRM: 4 a 6 semanas.
- Fase 3 - lote limitado R2 e UI de revisao/confirmacao: 3 a 5 semanas adicionais.
- Fase 4 - destrutivo R3/R4 com snapshots/restores por dominio: 8 a 12+ semanas, porque cada dominio precisa contrato proprio de backup/undo e teste de restore.

## Veredito

Viavel para leitura, diagnostico e navegacao com reuso alto do stack Autonomia/CRM AI atual. Parcialmente viavel para escritas pequenas e reversiveis depois de criar um action registry com envelope backend.

Nao e viavel liberar "autonomia ampla / agir por padrao" sobre a plataforma atual sem uma camada de seguranca anterior as escritas. O risco principal nao e o LLM errar texto; e o backend aceitar uma acao destrutiva valida demais, em conta/escopo valido, sem dry-run, backup, confirmacao e undo especifico.

Recomendacao de engenharia: tratar P5 como fase predecessora obrigatoria de qualquer EP de escrita. O primeiro release deve ser read-only + planos de acao; o segundo pode executar R1. R2/R3/R4 so depois de envelope, confirmacao e backup/snapshot por dominio.
