# V2 - Copiloto Autonom.ia: plano tecnico de implementacao

Documento para engenharia, baseado na leitura do codigo real deste fork Chatwoot v4.15.1.
Este plano nao implementa nada. Ele define os slices, arquivos e criterios para V2.

## Resumo executivo

V2 adiciona dois conceitos ao sistema de agentes Autonom.ia:

1. O Construtor passa a iniciar com escolhas explicitas de atuacao e conhecimento:
   `actuation = external|internal|both` e `with_knowledge = true|false`.
2. Agentes internos passam a ser copilotos da equipe, nao bots de atendimento ao cliente.
   Eles nao podem criar `AgentBot`, nao entram em `AgentBotInbox`, nao ficam presos a uma caixa
   e aparecem no seletor do widget "Copiloto Autonom.ia".
3. O Revisor de conhecimento nao precisa mudar. Ele ja roda por fonte, e a agregacao geral ja
   devolve confianca `0` quando nao ha fontes aceitas.
4. O Captain nativo deve ficar desligado por feature flag de conta (`captain_integration`) e o
   widget Autonom.ia deve reutilizar os componentes visuais de `components-next/copilot/*`,
   com container/store/API proprios no namespace Autonom.ia.

Principios obrigatorios:

- Sem regressao: defaults reproduzem o comportamento atual (`external + with_knowledge=true`).
- Uma unica migracao, aditiva, com backup antes e rollout pre-swap.
- Deploy somente com OK explicito do owner.
- Gate por `Crm::Config.enabled?` / `CRM_KANBAN_ENABLED` e `CRM_COPILOT_ENABLED`.
- Minimo toque em upstream: codigo novo em namespace Autonom.ia sempre que possivel.
- Testes reais por comportamento, nao apenas "200 ok".
- Codex review e screenshot por slice.

## Codigo verificado

V1 ja esta em producao como painel rapido:

- `app/services/autonomia/copilot/conversation_copilot.rb`
  - Tarefas atuais: `summarize`, `draft`, `rewrite`, `refine`.
  - `draft` usa `Autonomia::Agents::Copilot` quando existe `Autonomia::Agents::AgentInbox`
    para o inbox da conversa, senao cai em draft generico.
  - Nao levanta excecao para a UI: retorna `available: false`.
- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb`
  - `POST /api/v1/accounts/:account_id/autonomia/conversations/:conversation_id/copilot`.
  - Gate: `Crm::Config.enabled?` + `ENV.fetch('CRM_COPILOT_ENABLED', true)`.
  - `conversation_id` e `display_id`; `authorize @conversation, :show?`.
- `app/javascript/dashboard/routes/dashboard/crm/components/CrmCopilotPanel.vue`
  - Usa `AutonomiaCopilotAPI.run`.
  - Insere resposta com `BUS_EVENTS.INSERT_INTO_RICH_EDITOR`.
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue`
  - Monta `CrmCopilotPanel` quando `crmKanbanEnabled && currentChat.id`.

Construtor/Revisor:

- `app/javascript/dashboard/routes/dashboard/autonomia/components/AgentTypePicker.vue`
  - Hoje emite apenas `select(value)` com o tipo.
- `app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentBuilderPage.vue`
  - `onPickType(type)` chama `autonomiaBuildThreads/start({ type })`.
  - `startThread()` abre a thread sem mensagem para o Construtor falar primeiro.
- `app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb`
  - `create` chama `@thread.persist_agent_type!(params[:type])`.
  - Ja persiste `no_materials` e `force_close` quando esses params aparecem.
- `app/models/autonomia/agents/build_thread.rb`
  - `state` ja guarda `agent_type`, `no_materials_declared`, `force_close`.
- `app/services/autonomia/agents/builder.rb`
  - `MOTHER_INSTRUCTION` e `SKELETON_INSTRUCTIONS` assumem agente para cliente final.
  - `context_blocks` atual: `[skeleton_context, opening_context, knowledge_context,
    send_media_context, materials_status_context, turn_budget_context, adjust_context]`.
  - Ja existe caminho sem materiais: `no_materials_declared?`, `closing_phase?`,
    `force_close?`, `materials_status_context` e a regra `5.4 SEM MATERIAL`.
- `app/services/autonomia/agents/knowledge/reviewer.rb`
  - `review_source!` avalia uma fonte.
  - `review_input_text` inclui `Tipo do agente`, `Propósito do agente` e `type_scope_hint`.
  - `recompute_overall!` busca `accepted_sources.ready`.
  - `overall_confidence` retorna `0` quando `accepted_sources.empty?`.

Captain nativo:

- `app/javascript/dashboard/featureFlags.js`
  - `FEATURE_FLAGS.CAPTAIN = 'captain_integration'`.
- `app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue`
  - Exibe launcher somente com `FEATURE_FLAGS.CAPTAIN`.
- `app/javascript/dashboard/components/copilot/CopilotContainer.vue`
  - Exibe painel somente com `FEATURE_FLAGS.CAPTAIN`.
- `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js`
  - Rotas principais usam `meta.featureFlag = FEATURE_FLAGS.CAPTAIN`.
- Atencao: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` contem o grupo
  `name: 'Captain'` no array `menuItems` sem condicional local visivel. O slice V2.3 deve
  validar em runtime se o guard global/rota remove o item apos desligar `captain_integration`.
  Se o item continuar visivel, isso vira decisao do owner: aceitar um wrapper minimo no sidebar
  ou manter o item sem rota acessivel. A recomendacao principal continua ser desligar a feature
  por conta, sem editar upstream.

## Slices

### V2.1 - Construtor com atuacao e base

Objetivo:

- Tela inicial do builder com dois controles de nivel de tela:
  - Atuacao: `Externo (atende clientes)`, `Interno (copiloto da equipe)`.
  - Conhecimento: `Com base`, `Sem base`.
- Defaults: `external + with_knowledge=true`.
- Backend recebe e persiste hints no `BuildThread.state`.
- `Builder` gera agente externo como hoje e agente interno como copiloto da equipe.
- Inclui a migracao aditiva de `autonomia_agents.actuation`.

Arquivos tocados:

- FE:
  - `app/javascript/dashboard/routes/dashboard/autonomia/components/AgentTypePicker.vue`
  - `app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentBuilderPage.vue`
  - `app/javascript/dashboard/api/autonomia/buildThreads.js`
  - `app/javascript/dashboard/store/modules/autonomiaBuildThreads.js`
  - `app/javascript/dashboard/i18n/locale/en/agents.json`
- BE:
  - `db/migrate/YYYYMMDDHHMMSS_add_actuation_to_autonomia_agents.rb`
  - `db/schema.rb`
  - `app/models/autonomia/agents/agent.rb`
  - `app/models/autonomia/agents/build_thread.rb`
  - `app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb`
  - `app/services/autonomia/agents/builder.rb`
  - `docs/construtor_instruction_v2.md`
  - `app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder`

Migracao:

```ruby
class AddActuationToAutonomiaAgents < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :autonomia_agents, :actuation, :integer, null: false, default: 0
    add_index :autonomia_agents, %i[account_id actuation],
              name: 'idx_autonomia_agents_account_actuation',
              algorithm: :concurrently
  end

  def down
    remove_index :autonomia_agents, name: 'idx_autonomia_agents_account_actuation',
                                   algorithm: :concurrently if index_exists?(:autonomia_agents, %i[account_id actuation],
                                                                            name: 'idx_autonomia_agents_account_actuation')
    remove_column :autonomia_agents, :actuation if column_exists?(:autonomia_agents, :actuation)
  end
end
```

Modelo:

- Em `Autonomia::Agents::Agent`:
  - Adicionar `enum actuation: { external: 0, internal: 1, both: 2 }, _prefix: :actuation`.
  - Default DB `external` mantem agentes existentes operando igual.
  - Adicionar `store_accessor :config, :with_knowledge` para refletir o build hint no JSON.
  - Serializer deve expor `actuation` e `with_knowledge` sem expor `instruction/scaffold`.

BuildThread:

- Adicionar `store_accessor :state, :actuation, :with_knowledge`.
- Substituir ou complementar `persist_agent_type!(type)` com algo como
  `persist_start_options!(type:, actuation:, with_knowledge:)`.
- Normalizar:
  - `type`: existente, via `Agent::AGENT_TYPES`, fallback `custom`.
  - `actuation`: `external|internal|both`, fallback `external`.
  - `with_knowledge`: booleano, fallback `true`.
- Quando `with_knowledge == false`, gravar tambem `no_materials_declared = true`
  ja na abertura da thread. Isso usa o gate existente do `Builder` e evita perguntar por documentos
  no primeiro turno.

Builder:

- Adicionar `actuation_context` no inicio de `context_blocks`:

```ruby
def context_blocks
  [actuation_context, skeleton_context, opening_context, knowledge_context, send_media_context,
   materials_status_context, turn_budget_context, adjust_context].compact_blank
end
```

- Criar `builder_actuation`, lendo primeiro `@thread.agent&.actuation`, depois
  `@thread.state['actuation']`, fallback `external`.
- Criar `with_knowledge?`, lendo `@thread.state['with_knowledge']`, fallback `true`.
- `actuation_context` deve produzir um bloco de `CONTEXTO INTERNO (nao e fala do usuario). ATUACAO...`.
  Conteudo esperado:
  - `external`: comportamento atual, agente atende cliente final e pode ser conectado a inbox.
  - `internal`: agente e copiloto da equipe; ajuda o operador humano com analise, resumo,
    proximos passos, rascunhos e consulta a conhecimento; nao fala diretamente com cliente;
    `greeting`, `handoff_rule` e `fallback_message` devem ser vazios ou neutros; nao criar
    linguagem de auto-atendimento.
  - `both`: agente pode atender cliente quando conectado e tambem ser usado como copiloto;
    manter campos externos preenchidos, mas evitar instrucoes que o tornem dependente de inbox.

- Atualizar `MOTHER_INSTRUCTION` em pontos pequenos e explicitos:
  - Secao 3, "O QUE VOCE RECEBE": adicionar que o input pode incluir `CONTEXTO INTERNO: ATUACAO`.
  - Secao 7, antes de `7.1`: adicionar regra para atuacao interna: "se ATUACAO=internal,
    redija a instruction para assistir o operador humano, nao para responder como cliente-facing".
  - Secao 8, campos de saida: para `internal`, `greeting`, `fallback_message` e `handoff_rule`
    podem ser string vazia/neutra; `starter_questions` devem ser perguntas/comandos internos
    para a equipe.
  - Manter `docs/construtor_instruction_v2.md` sincronizado com `MOTHER_INSTRUCTION`.

- Atualizar `Builder.map_attributes(parsed)`:
  - Incluir `actuation: builder_actuation` no fechamento.
  - Incluir `config: { 'guardrails' => ..., 'with_knowledge' => with_knowledge? }`.
  - Garantir que defaults sem params gerem exatamente o mesmo agente externo atual.

Testavel em V2.1:

- `AgentTypePicker` mostra cards maiores e dois radiogroups com defaults corretos.
- Clique em card emite `{ type, actuation, withKnowledge }`.
- `AgentBuilderPage#onPickType` chama `autonomiaBuildThreads/start({ type, actuation, with_knowledge })`.
- `BuildThreadsController#create` grava `state['actuation']`, `state['with_knowledge']` e,
  para `with_knowledge=false`, `state['no_materials_declared']=true`.
- `Builder#build_input` contem `CONTEXTO INTERNO ... ATUACAO`.
- `external + with_knowledge=true` nao muda o texto/fluxo esperado.

### V2.2 - Agente interno seguro no Hub/Painel

Objetivo:

- Agentes `internal` nunca criam `AgentBot`, `AgentBotInbox` ou `Autonomia::Agents::AgentInbox`.
- Agentes `internal` nao exibem fluxo de conectar caixa.
- Agentes `both` continuam conectaveis e tambem ficam disponiveis para copiloto.
- Hub e painel deixam claro se o agente e externo, interno ou ambos.

Arquivos tocados:

- BE:
  - `app/controllers/api/v1/accounts/autonomia/agents_controller.rb`
  - `app/controllers/api/v1/accounts/autonomia/agents/channels_controller.rb`
  - `app/services/autonomia/agents/operate/inbox_connector.rb`
  - `app/jobs/autonomia/agents/operate/reply_job.rb` (defesa em profundidade opcional)
  - `app/services/autonomia/agents/operate.rb` (defesa em profundidade opcional)
  - `app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder`
  - `app/views/api/v1/accounts/autonomia/agents/channels/index.json.jbuilder`
- FE:
  - `app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentsHubPage.vue`
  - `app/javascript/dashboard/routes/dashboard/autonomia/components/AgentCard.vue`
  - `app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentPanelPage.vue`
  - `app/javascript/dashboard/routes/dashboard/autonomia/components/builder/BuilderReview.vue`
  - `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelChannels.vue`
  - `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelTune.vue`
  - `app/javascript/dashboard/i18n/locale/en/agents.json`

Backend:

- `AgentsController#agent_params` deve permitir `:actuation` para modo manual/edicao.
- `InboxConnector#connect!` deve bloquear `@agent.actuation_internal?` com erro especifico
  `:internal_agent_not_connectable`. Nao criar nenhum registro antes desse retorno.
- `ChannelsController#index`:
  - Para `internal`, retornar `payload: []` e `eligible_inboxes: []` ou um flag `connectable: false`.
  - Para `external`/`both`, manter o comportamento atual.
- `ReplyJob#eligible_agent_inbox` e `Operate.active_for?` podem ganhar guarda extra:
  `agent.actuation_external? || agent.actuation_both?`. Tecnicamente `internal` nao tera
  `AgentInbox`, mas a guarda evita resposta automatica se dados forem criados manualmente por erro.

Frontend:

- `BuilderReview.vue`:
  - Para `internal`, esconder o bloco "Conectar" e mostrar CTA de finalizar/abrir painel.
  - Nao exigir `selectedInbox`.
  - `greeting` fica opcional/vazio.
- `AgentPanelPage.vue`:
  - Remover ou desabilitar aba `channels` quando `agent.actuation === 'internal'`.
  - Para `both`, manter aba.
- `PanelChannels.vue`:
  - Se receber agente interno, mostrar estado informativo e nao botao de conectar.
- `AgentCard.vue`:
  - Adicionar badge de atuacao.
  - Para canais, interno deve mostrar "Copiloto interno" ou contagem de canais como 0 sem sugerir erro.
- `PanelTune.vue`:
  - Expor `actuation` de forma controlada se o owner quiser edicao pos-criacao.
  - Se permitir troca de `external -> internal`, desconectar inboxes existentes antes ou bloquear com mensagem.
    Preferencia inicial: bloquear troca quando houver canais conectados.

Testavel em V2.2:

- Criar agente interno manual ou via builder e chamar endpoint de conectar canal:
  - resposta `422` com erro especifico;
  - `AgentBot.count`, `AgentBotInbox.count`, `Autonomia::Agents::AgentInbox.count` nao mudam.
- Criar agente externo e conectar canal continua criando os tres registros como hoje.
- Criar agente `both` e conectar canal continua funcionando.
- UI de review para interno nao mostra seletor de inbox.
- Aba `channels` nao aparece para interno.

### V2.3 - Widget "Copiloto Autonom.ia" e Captain OFF

Objetivo:

- Desligar Captain nativo por conta, sem patch upstream sempre que possivel.
- Criar widget Autonom.ia com launcher/container proprios.
- Reutilizar a UI/visual do widget do Captain (a "telinha", incluindo o icone do launcher)
  de `app/javascript/dashboard/components-next/copilot/*` sem mudar a aparencia.
- TITULO DO DRAWER = NOME DO AGENTE selecionado (o nome definido na criacao do agente),
  NAO uma string fixa "Copiloto Autonom.ia". Espelha o Captain, que mostra `activeAssistant.name`
  no `ToggleCopilotAssistant`. Sem colisao de nome porque o Captain nativo esta desligado.
- Backend de chat conversation-scoped usa agente interno/both selecionado e contexto da conversa.

Arquivos tocados:

- BE:
  - `config/routes.rb`
  - `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb`
  - `app/services/autonomia/copilot/conversation_copilot.rb` (manter quick-actions)
  - Novo: `app/services/autonomia/copilot/conversation_chat.rb`
  - `app/controllers/dashboard_controller.rb`
  - `app/javascript/shared/store/globalConfig.js`
  - `app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder`
- FE:
  - `app/javascript/dashboard/api/autonomiaCopilot.js`
  - Novo: `app/javascript/dashboard/store/modules/autonomiaCopilot.js`
  - Novo: `app/javascript/dashboard/components/autonomia/copilot/AutonomiaCopilotLauncher.vue`
  - Novo: `app/javascript/dashboard/components/autonomia/copilot/AutonomiaCopilotContainer.vue`
  - `app/javascript/dashboard/routes/dashboard/Dashboard.vue`
  - `app/javascript/dashboard/components-next/copilot/Copilot.vue`
  - `app/javascript/dashboard/components-next/copilot/CopilotInput.vue`
  - `app/javascript/dashboard/components-next/copilot/CopilotAssistantMessage.vue`
  - `app/javascript/dashboard/components-next/copilot/CopilotAgentMessage.vue`
  - `app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue`
  - `app/javascript/dashboard/components-next/copilot/ToggleCopilotAssistant.vue`
  - `app/javascript/dashboard/i18n/locale/en/agents.json`
  - `app/javascript/dashboard/i18n/locale/en/crm.json` ou arquivo i18n equivalente para o widget.

Captain OFF:

- Operacao reversivel por conta:

```ruby
Account.find(<ACCOUNT_ID>).disable_features!('captain_integration')
```

- Rollback:

```ruby
Account.find(<ACCOUNT_ID>).enable_features!('captain_integration')
```

- Validar com screenshot:
  - Rotas Captain bloqueadas pelo `meta.featureFlag`.
  - Launcher nativo some.
  - Container nativo some.
  - Sidebar "Captain" some. Se nao sumir, registrar o desvio e pedir OK do owner para um wrapper
    minimo em `Sidebar.vue`; nao fazer esse patch silenciosamente.

Backend do chat:

- Manter `POST .../copilot` atual para quick-actions V1.
- Adicionar rotas conversation-scoped:
  - `GET /autonomia/conversations/:conversation_id/copilot/agents`
  - `POST /autonomia/conversations/:conversation_id/copilot/chat`
- Reusar `ensure_copilot_enabled` e `set_conversation`.
- `agents` lista somente agentes da conta com:
  - `actuation IN internal,both`;
  - `status active`;
  - `has_instruction = true`;
  - decisao pendente: exigir `enabled=true` ou nao. Recomendacao inicial: nao exigir `enabled`,
    porque `enabled` hoje significa auto-resposta em inbox; para interno basta `active + instruction`.
- `chat` recebe:
  - `agent_id`;
  - `message`;
  - `history` local do widget, limitado e saneado.
- `ConversationChat`:
  - Valida agente dentro da conta e `internal/both`.
  - Monta transcript da conversa usando a mesma disciplina de V1:
    `messages.chat.where.not(content: [nil, '']).order(:created_at).last(MAX_MESSAGES)`.
  - Limita transcript em chars como `ConversationCopilot::MAX_TRANSCRIPT`.
  - Chama `Autonomia::Agents::Copilot` ou `Autonomia::Agents::Answerer` com:
    - agente selecionado;
    - prompt do operador;
    - bloco de contexto da conversa atual como dado, nao instrucao;
    - historico local do widget.
  - Retorna JSON no shape facil para FE:
    `{ id, message_type: 'assistant', message: { content, reply_suggestion }, grounded, available }`.
  - Nao logar conteudo da conversa nem telefone completo.

Frontend do widget:

- `AutonomiaCopilotLauncher.vue`:
  - Usa `ui_settings.is_autonomia_copilot_panel_open`, nao `is_copilot_panel_open`, para nao colidir com Captain.
  - Gate: `globalConfig.crmKanbanEnabled === true` e `globalConfig.crmCopilotEnabled === true`.
  - Nao aparecer em telas onde o container ja esta aberto.
- `AutonomiaCopilotContainer.vue`:
  - Busca agentes internos/both via endpoint novo.
  - TITULO/HEADER do drawer = `activeAgent.name` (nome dado na criacao), via prop opcional
    `assistantName`/`title` nos componentes compartilhados; NUNCA string fixa de marca.
  - Usa `preferred_autonomia_copilot_agent_id` em `ui_settings`, espelhando o padrao
    `preferred_captain_assistant_id`.
  - Fecha com `is_autonomia_copilot_panel_open=false`.
  - Usa `currentChat` para passar `conversation_id`.
  - Mantem mensagens em store local `autonomiaCopilot`.
- Componentes `components-next/copilot/*`:
  - Alteracoes devem ser props opcionais, backward-compatible:
    - `title`, `assistantName`, `i18nPrefix`, `closeSettingKey`, `emptyStateRoute`, `icon`.
  - Default deve continuar `CAPTAIN.*` e `is_copilot_panel_open`, para nao quebrar Captain se for reativado.
  - `CopilotAssistantMessage.vue` ja sabe inserir no editor via `BUS_EVENTS.INSERT_INTO_RICH_EDITOR`
    ou `INSERT_INTO_NORMAL_EDITOR`; manter isso, mas controlar `reply_suggestion`.

Gate de ENV no FE:

- Hoje o FE do V1 so conhece `crmKanbanEnabled`; `CRM_COPILOT_ENABLED=false` so bloqueia no backend.
- Para V2.3, expor `CRM_COPILOT_ENABLED` em `DashboardController#app_config` e parsear em
  `globalConfig.js` como `crmCopilotEnabled`.
- Usar `crmKanbanEnabled && crmCopilotEnabled` para launcher/container e manter o backend como autoridade.

Testavel em V2.3:

- Com `CRM_COPILOT_ENABLED=false`, endpoint retorna 404 e launcher/container nao montam.
- Com `CRM_KANBAN_ENABLED=false`, endpoint retorna 404 e launcher/container nao montam.
- Selector lista interno/both, nao lista externo.
- Chat com agente interno inclui contexto da conversa e retorna resposta.
- Botao "usar" insere texto no editor quando `reply_suggestion=true`.
- Desligar `captain_integration` remove launcher/container nativos; sidebar deve ser validado por screenshot.

## Lista arquivo a arquivo

### Backend

- `db/migrate/YYYYMMDDHHMMSS_add_actuation_to_autonomia_agents.rb`
  - Adiciona `actuation` inteiro com default `0`.
  - Adiciona indice `account_id, actuation`.
  - `disable_ddl_transaction!` para indice concorrente.

- `app/models/autonomia/agents/agent.rb`
  - Enum `actuation`.
  - `store_accessor :config, :with_knowledge`.
  - Helpers/scopes opcionais: `copilot_selectable`, `connectable_to_inbox`.

- `app/models/autonomia/agents/build_thread.rb`
  - `store_accessor :state, :actuation, :with_knowledge`.
  - Metodo de persistencia dos start options.
  - Default estrito para compatibilidade.

- `app/controllers/api/v1/accounts/autonomia/agents/build_threads_controller.rb`
  - `create` passa `type`, `actuation`, `with_knowledge` para o model.
  - `with_knowledge=false` semeia `no_materials_declared`.
  - Mantem `persist_no_materials_flag` e `persist_force_close_flag` para continuacoes.

- `app/services/autonomia/agents/builder.rb`
  - `actuation_context`.
  - `builder_actuation`.
  - `with_knowledge?`.
  - Atualizacao pequena da `MOTHER_INSTRUCTION`.
  - `map_attributes` grava `actuation` e `config['with_knowledge']`.
  - `state_for` expoe `draft_config['actuation']` e `draft_config['with_knowledge']`.

- `docs/construtor_instruction_v2.md`
  - Sincronizar com `MOTHER_INSTRUCTION`, como o proprio doc exige.

- `app/controllers/api/v1/accounts/autonomia/agents_controller.rb`
  - Permitir `:actuation`.
  - Bloquear edicao perigosa se trocar para `internal` com canais conectados, ou desconectar explicitamente
    se esse for o produto aprovado.

- `app/views/api/v1/accounts/autonomia/agents/_agent.json.jbuilder`
  - Expor `actuation`.
  - Expor `with_knowledge`.

- `app/controllers/api/v1/accounts/autonomia/agents/channels_controller.rb`
  - Nao listar/conectar canais para `internal`.
  - Retornar shape estavel para FE.

- `app/services/autonomia/agents/operate/inbox_connector.rb`
  - Bloquear `internal` antes de criar `AgentBot`.
  - Manter `external` e `both` intactos.

- `app/jobs/autonomia/agents/operate/reply_job.rb`
  - Defesa opcional: nao responder se agente nao for `external` ou `both`.

- `app/services/autonomia/agents/operate.rb`
  - Defesa opcional no `active_for?`.

- `config/routes.rb`
  - Adicionar `copilot/agents` e `copilot/chat` conversation-scoped.
  - Preservar `POST .../copilot` atual.

- `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb`
  - Manter `create` V1.
  - Adicionar `agents` e `chat`.
  - Reusar gate e autorizacao da conversa.

- `app/services/autonomia/copilot/conversation_chat.rb`
  - Novo servico para chat do widget.
  - Isola transcript, agente selecionado e resposta.

- `app/controllers/dashboard_controller.rb`
  - Expor `CRM_COPILOT_ENABLED`.

- `app/javascript/shared/store/globalConfig.js`
  - Parsear `crmCopilotEnabled`.

### Frontend

- `app/javascript/dashboard/routes/dashboard/autonomia/components/AgentTypePicker.vue`
  - Cards maiores.
  - Radiogroups de atuacao e conhecimento.
  - Estado local default `external`, `withKnowledge=true`.
  - Emitir objeto.

- `app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentBuilderPage.vue`
  - `onPickType(payload)` guarda `agentType`, `actuation`, `withKnowledge`.
  - `startThread()` despacha `type`, `actuation`, `with_knowledge`.
  - Review nao busca canais para `internal`.

- `app/javascript/dashboard/api/autonomia/buildThreads.js`
  - `create` ja passa `...rest`; documentar `actuation` e `with_knowledge`.

- `app/javascript/dashboard/store/modules/autonomiaBuildThreads.js`
  - Testar passagem de `actuation`/`with_knowledge`.
  - Preservar polling e fases.

- `app/javascript/dashboard/routes/dashboard/autonomia/components/builder/BuilderReview.vue`
  - Branch visual para `internal`.
  - Greeting opcional.
  - Sem seletor de inbox para interno.

- `app/javascript/dashboard/routes/dashboard/autonomia/pages/AgentPanelPage.vue`
  - Ocultar aba `channels` para interno.

- `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelChannels.vue`
  - Estado informativo para interno.

- `app/javascript/dashboard/routes/dashboard/autonomia/components/AgentCard.vue`
  - Badge de atuacao.

- `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelTune.vue`
  - Exibir/editar atuacao conforme decisao de produto.

- `app/javascript/dashboard/api/autonomiaCopilot.js`
  - Adicionar `listAgents(conversationId)` e `chat(conversationId, payload)`.

- `app/javascript/dashboard/store/modules/autonomiaCopilot.js`
  - Store local de mensagens do widget.
  - Preferir shape dos componentes Captain:
    `message_type: 'user'|'assistant'|'assistant_thinking'`.

- `app/javascript/dashboard/components/autonomia/copilot/AutonomiaCopilotLauncher.vue`
  - Launcher proprio, sem `FEATURE_FLAGS.CAPTAIN`.

- `app/javascript/dashboard/components/autonomia/copilot/AutonomiaCopilotContainer.vue`
  - Container proprio, usa endpoints Autonom.ia.

- `app/javascript/dashboard/routes/dashboard/Dashboard.vue`
  - Montar launcher/container Autonom.ia.
  - Gate por `crmKanbanEnabled && crmCopilotEnabled`.
  - Manter Captain nativo intocado, mas desligado por feature flag.

- `app/javascript/dashboard/components-next/copilot/*.vue`
  - Props opcionais backward-compatible para textos/close key/nome/icone.

- `app/javascript/dashboard/i18n/locale/en/agents.json`
  - Textos de atuacao, conhecimento, estados internos e widget.

- `app/javascript/dashboard/i18n/locale/en/crm.json`
  - Se o namespace do widget ficar junto do CRM/copilot, adicionar textos aqui.

## Construtor em detalhe

### Onde entra o bloco de atuacao

No `Builder`, inserir `actuation_context` como primeiro bloco de `context_blocks`.
Motivo: ele qualifica todos os blocos seguintes, inclusive `skeleton_context` e `opening_context`.

Ordem proposta:

1. `actuation_context`
2. `skeleton_context`
3. `opening_context`
4. `knowledge_context`
5. `send_media_context`
6. `materials_status_context`
7. `turn_budget_context`
8. `adjust_context`

### Como `with_knowledge=false` liga no fluxo existente

Fluxo atual ja resolve "sem material" por `no_materials_declared?`.
Nao criar um novo gate.

Na abertura:

- FE envia `with_knowledge: false`.
- `BuildThreadsController#create` persiste `state['with_knowledge']=false`.
- O mesmo create grava `state['no_materials_declared']=true`.
- `opening_context` recebe uma linha adicional quando `with_knowledge? == false`:
  "o usuario escolheu criar sem base; nao peca documentos no primeiro turno, colete apenas o essencial".
- `materials_status_context` passa a informar que o usuario declarou nao ter material desde o inicio.
- `closing_phase?` ja fica verdadeiro por `no_materials_declared?`, preservando o caminho existente.

### Matriz de teste obrigatoria

| Cenario | Params de start | Estado esperado | Comportamento do Builder | Resultado esperado |
|---|---|---|---|---|
| Externo + com base | `actuation=external`, `with_knowledge=true` ou defaults ausentes | `actuation=external`, `with_knowledge=true`, `no_materials_declared=false` | Fluxo atual, pode pedir materiais e gera atendimento cliente-facing | Agente externo conectavel, campos `greeting/handoff/fallback` preenchidos como hoje |
| Externo + sem base | `actuation=external`, `with_knowledge=false` | `no_materials_declared=true` desde o create | Nao insiste em documentos; fecha usando conversa e orienta handoff quando faltar informacao | Agente externo conectavel, `config.with_knowledge=false`, sem travar por ausencia de fonte |
| Interno + com base | `actuation=internal`, `with_knowledge=true` | `actuation=internal`, `with_knowledge=true` | Usa KB para ajudar operador humano; nao redige agente que fala como cliente final | Agente interno nao conectavel, aparece no seletor do Copiloto Autonom.ia |
| Interno + sem base | `actuation=internal`, `with_knowledge=false` | `actuation=internal`, `no_materials_declared=true` | Nao pede documentos; gera copiloto interno baseado na conversa/config fornecida | Agente interno sem canais, `knowledge_confidence` pode ficar 0, ainda selecionavel se ativo/instruido |

## Revisor: sem mudanca necessaria

Nao alterar `app/services/autonomia/agents/knowledge/reviewer.rb` para V2.

Razoes verificadas no codigo:

- O Revisor roda por fonte em `review_source!`, nao por atuacao do agente.
- `review_input_text` ja e type-aware:
  - inclui `Tipo do agente: #{@agent&.agent_type}`;
  - inclui `Propósito do agente`;
  - inclui `type_scope_hint`, derivado de `Autonomia::Agents::Builder.skeleton_for`.
- A agregacao `recompute_overall!(agent)` opera somente sobre `agent.accepted_sources.ready`.
- `overall_confidence(accepted_sources)` retorna `0` se `accepted_sources.empty?`.
- Quando nao ha fontes aceitas, `topic_map_for` retorna `summary: ''` e `topic_map: []`.
- Isso cobre `with_knowledge=false` sem migracao nem prompt novo no Revisor.

Teste de regressao opcional:

- Um agente interno sem fontes deve manter `knowledge_confidence = 0` apos recompute.
- Um agente interno com fonte aceita deve receber `topic_map` igual a qualquer agente do mesmo tipo.

## Riscos e rollbacks

### V2.1

Riscos:

- Prompt interno ainda gerar textos cliente-facing se o bloco de atuacao for fraco.
- `with_knowledge=false` fechar cedo demais sem coletar objetivo/nome.
- Migracao em producao sem backup.

Mitigacoes:

- Testar a matriz 4 cenarios com respostas estruturadas fake e, depois, teste manual real.
- Defaults sem params continuam `external + with_knowledge=true`.
- Backup antes da migracao.

Rollback:

- Rollback de codigo ignora a coluna nova; agentes existentes continuam `external`.
- Se necessario, rollback DB remove indice e coluna, mas preferir deixar coluna aditiva inerte.

### V2.2

Riscos:

- Agente interno criado antes do bloqueio ser conectado manualmente por API.
- UI esconder canais para `both` por engano.
- Edicao de atuacao quebrar agente ja conectado.

Mitigacoes:

- Guard no backend antes de criar `AgentBot`.
- Specs contando registros de `AgentBot`, `AgentBotInbox` e `AgentInbox`.
- Bloquear troca para `internal` quando houver canais ate o owner aprovar fluxo de desconexao.

Rollback:

- Reverter UI/guards. Como `actuation` default e `external`, operacao antiga volta.
- Se um agente interno foi conectado por erro, usar desconexao existente do `InboxConnector`
  ou remover vinculo com cuidado, preservando conversas e fazendo `bot_handoff!`.

### V2.3

Riscos:

- Desligar `captain_integration` nao remover o item de sidebar por causa do trecho estatico em `Sidebar.vue`.
- Reuso dos componentes `components-next/copilot/*` vazar strings "Captain".
- Widget inserir no editor uma resposta que era apenas analise interna.
- Endpoint de chat aceitar agente externo e virar canal de resposta indevido.

Mitigacoes:

- Screenshot antes/depois do Captain OFF.
- Props opcionais com defaults Captain nos componentes compartilhados.
- `reply_suggestion` controlado pelo backend/FE; botao "usar" so quando a resposta for rascunho.
- Query do selector e validacao do `chat` exigem `internal/both`.

Rollback:

- `CRM_COPILOT_ENABLED=false` desliga endpoints e UI Autonom.ia.
- Reabilitar Captain com `Account#enable_features!('captain_integration')`.
- Remover launcher/container Autonom.ia do `Dashboard.vue`; store e endpoints ficam inertes.

## Rollout de migracao

1. Confirmar OK explicito do owner.
2. Fazer backup/snapshot do banco antes da migracao.
3. Construir a imagem nova.
4. Pre-swap: com a imagem antiga ainda servindo trafego, rodar a migracao da imagem nova contra o banco:

```bash
bundle exec rails db:migrate
```

5. Como a migracao e aditiva, a imagem antiga continua compativel enquanto a coluna existe sem ser usada.
6. Trocar web e Sidekiq para a imagem nova.
7. Validar:
   - builder default externo com base;
   - builder interno sem base;
   - agente interno nao conecta inbox;
   - widget Autonom.ia com `CRM_COPILOT_ENABLED=true`;
   - Captain nativo desligado.

## Plano de testes

Ruby:

- `spec/models/autonomia/agents/agent_spec.rb`
  - default `actuation=external`;
  - enum aceita `external/internal/both`;
  - serializer nao expoe `instruction/scaffold`.
- `spec/requests/api/v1/accounts/autonomia/agents/build_threads_spec.rb`
  - create default preserva comportamento;
  - create com `with_knowledge=false` grava `no_materials_declared=true`;
  - feature off retorna 404;
  - usuario nao-admin retorna 403/NotAuthorized.
- `spec/services/autonomia/agents/builder_spec.rb`
  - `build_input` inclui `actuation_context`;
  - `opening_context` nao pede docs quando sem base;
  - `map_attributes` grava `actuation` e `config.with_knowledge`;
  - matriz 4 cenarios.
- `spec/services/autonomia/agents/operate/inbox_connector_spec.rb`
  - interno nao cria bot/vinculo;
  - externo continua conectando;
  - both continua conectando.
- `spec/requests/api/v1/accounts/autonomia/conversation_copilot_spec.rb`
  - chat bloqueado por flag;
  - selector filtra interno/both;
  - chat rejeita agente externo;
  - chat respeita autorizacao `show?` da conversa.

JS/Vue:

- `app/javascript/dashboard/routes/dashboard/autonomia/components/AgentTypePicker.spec.js`
  - defaults de radiogroup;
  - emissao do objeto.
- `app/javascript/dashboard/store/modules/specs/autonomia/buildThreads.spec.js`
  - `start` passa `actuation` e `with_knowledge`;
  - `declareNoMaterials` e `completeMaterials` preservam flags corretas.
- `app/javascript/dashboard/api/specs/autonomiaCopilot.spec.js`
  - URLs de `agents` e `chat`.
- `app/javascript/dashboard/components/autonomia/copilot/AutonomiaCopilotContainer.spec.js`
  - carrega agentes;
  - salva `preferred_autonomia_copilot_agent_id`;
  - envia mensagem com `conversation_id` e `agent_id`.
- `app/javascript/dashboard/routes/dashboard/Dashboard.spec.js` se houver padrao local viavel;
  caso contrario, validar por screenshot Playwright/manual.

Comandos:

```bash
eval "$(rbenv init -)"
bundle exec rspec spec/models/autonomia/agents/agent_spec.rb
bundle exec rspec spec/requests/api/v1/accounts/autonomia/agents/build_threads_spec.rb
bundle exec rspec spec/services/autonomia/agents/builder_spec.rb
bundle exec rspec spec/services/autonomia/agents/operate/inbox_connector_spec.rb
bundle exec rspec spec/requests/api/v1/accounts/autonomia/conversation_copilot_spec.rb
pnpm test app/javascript/dashboard/store/modules/specs/autonomia/buildThreads.spec.js
pnpm eslint
```

## Screenshots por slice

- V2.1:
  - Agent type picker desktop.
  - Agent type picker mobile.
  - Primeiro turno do Construtor para `external+base` e `internal+sem base`.
- V2.2:
  - Review de agente interno sem bloco de conectar.
  - Hub com badge interno/externo.
  - Painel de agente interno sem aba canais.
- V2.3:
  - Captain nativo off: sidebar/launcher/container.
  - Launcher "Copiloto Autonom.ia".
  - Container aberto com selector de agente interno.
  - Insercao no editor quando `reply_suggestion=true`.

## Perguntas abertas para o owner

1. Agente `both` deve ser criado pela UI ja no V2 ou fica reservado para edicao/admin?
2. Agente interno precisa de `enabled=true` para aparecer no seletor, ou `active + has_instruction`
   basta?
3. O usuario pode trocar `actuation` depois de criado? Se sim, qual regra quando o agente externo
   ja tem inbox conectado?
4. O botao "usar resposta" deve aparecer em toda resposta do copiloto interno ou somente quando o
   operador pedir explicitamente um rascunho?
5. Se desligar `captain_integration` nao remover o item estatico de `Sidebar.vue`, o owner aprova
   um guard minimo nesse arquivo?
6. Textos devem seguir a regra do projeto de atualizar somente locale `en`, ou esta customizacao
   pode tambem atualizar `pt_BR` por ser produto Autonom.ia em PT-BR?
7. O widget deve ficar visivel fora da rota de conversa ou apenas conversation-scoped enquanto houver
   `currentChat`?
