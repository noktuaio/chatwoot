# Sondagem P2 — UI Action Bus / UI Registry

Data: 2026-06-20  
Escopo lido: `app/javascript` do fork Chatwoot v4.15.1 customizado. Não houve implementação.

## Resumo executivo

O pilar é viável, mas não como "robô DOM genérico" no estado atual.

O frontend é bem endereçável por rota: há uma árvore clara de Vue Router com rotas nomeadas, `frontendURL`, `accountScopedRoute`, `meta.permissions` e vários gates por feature flag/ENV. Isso dá uma boa base para `navigate` e `open_surface`.

O ponto fraco é controle fino da UI: a cobertura de `data-testid` é praticamente inexistente nas telas operacionais. A maioria das ações de formulário depende de `v-model`, refs locais, modais e componentes compostos sem contrato externo. Para ações determinísticas, o caminho correto é um UI Registry pequeno, allowlisted, por superfície, com handlers estruturados e poucos targets estáveis adicionados apenas nas telas priorizadas.

Veredito: começar por 2 ou 3 superfícies de baixo churn e alto valor, não por cobertura geral do Chatwoot.

## Evidências quantitativas

### Cobertura de `data-testid`

Comando-base: `rg -n "data-testid" app/javascript`.

- `app/javascript` tem 4.870 arquivos.
- Existem 17 ocorrências de `data-testid`.
- Elas aparecem em 11 arquivos.
- Isso cobre ~0,23% dos arquivos de `app/javascript`.
- Em `app/javascript/dashboard/routes/dashboard` há 474 arquivos e só 7 ocorrências.
- Não há `data-testid` nas áreas sondadas de `settings/inbox`, `settings/automation`, `contacts`, `autonomia`, `campaigns` ou `components/autonomia`.

Distribuição:

- 7 ocorrências em `app/javascript/v3/views`.
- 7 ocorrências em `app/javascript/dashboard/routes`.
- 2 ocorrências em `app/javascript/dashboard/components`.
- 1 ocorrência em `app/javascript/dashboard/components-next`.

Arquivos com `data-testid`:

- `app/javascript/v3/views/login/Index.vue`: `email_input`, `password_input`, `submit_button`.
- `app/javascript/v3/views/auth/password/Edit.vue`: `submit_button`.
- `app/javascript/v3/views/auth/verify-email/Index.vue`: `resend_email_button`.
- `app/javascript/v3/views/auth/reset/password/Index.vue`: `submit_button`.
- `app/javascript/v3/views/auth/signup/components/Signup/Form.vue`: `submit_button`.
- `app/javascript/dashboard/components/auth/MfaVerification.vue`: `backup_code_input`, `submit_button`.
- `app/javascript/dashboard/routes/dashboard/settings/labels/AddLabel.vue`: `label-title`, `label-description`, `label-submit`.
- `app/javascript/dashboard/routes/dashboard/settings/integrations/DashboardApps/DashboardAppModal.vue`: `app-title`, `app-url`.
- `app/javascript/dashboard/routes/dashboard/settings/agentBots/components/AgentBotModal.vue`: `label-submit`.
- `app/javascript/dashboard/routes/dashboard/crm/components/calendar/CrmCalendarAgenda.vue`: `agenda-loading`.
- `app/javascript/dashboard/components-next/changelog-card/StackedChangelogCard.vue`: `changelog-card`.

Conclusão: hoje não existem targets estáveis suficientes para operar telas reais por seletor. Qualquer automação ampla cairia em texto, classes Tailwind, estrutura do DOM ou ordem de componentes, todos frágeis contra upgrades upstream.

Um ponto positivo: `components-next/button/Button.vue` passa atributos via `v-bind="filteredAttrs"` para o `<button>`, e `components-next/input/Input.vue` passa `$attrs` para o `<input>`. Ou seja, adicionar `data-testid` em botões/inputs escolhidos é baixo impacto quando a superfície já usa esses componentes.

## Roteamento e superfícies endereçáveis

Arquivos principais:

- `app/javascript/dashboard/routes/index.js`
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- `app/javascript/dashboard/helper/URLHelper.js`
- `app/javascript/dashboard/composables/useAccount.js`
- `app/javascript/dashboard/helper/routeHelpers.js`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/components-next/sidebar/provider.js`

Estrutura observada:

- `routes/index.js` cria `createRouter({ history: createWebHistory(), routes })`.
- `dashboard.routes.js` monta `frontendURL('accounts/:accountId')` em `Dashboard.vue` e agrega módulos: conversations, settings, contacts, CRM, Autonomia, companies, search, notifications, helpcenter, campaigns, captain.
- `frontendURL(path)` prefixa tudo com `/app/`.
- `useAccount.accountScopedRoute(name, params, query)` gera `{ name, params: { accountId, ...params }, query }`.
- `Sidebar.vue` usa fortemente `accountScopedRoute`, então a navegação por nome de rota já é o padrão.
- `provider.js` resolve `meta.permissions`, `meta.featureFlag` e `meta.installationTypes` via `router.resolve`.
- `routeHelpers.js` valida acesso com `meta.permissions` e redireciona para uma rota permitida.

Contagem textual dos arquivos de rota:

- 32 arquivos `*.routes.js`/`routes.js` sob `app/javascript/dashboard/routes/dashboard`.
- 1 rota adicional em `app/javascript/dashboard/modules/search/search.routes.js`.
- Total considerado: 33 arquivos de rota.
- 145 declarações de `name:` ancoradas em arquivos de rota.
- 142 nomes de rota únicos.
- 189 linhas `path:` ancoradas em arquivos de rota.
- 101 linhas `permissions:`.
- 53 linhas `featureFlag:`.
- 112 linhas `meta:`.
- 18 `beforeEnter:`.

Rotas/superfícies relevantes:

- Conversas: `conversation.routes.js` tem rotas para dashboard, inbox, label, team, custom view, mentions, unattended e participating.
- Contacts: `contacts/routes.js` expõe `contacts_dashboard_index`, `contacts_dashboard_active`, segmentos, labels, edição e a rota customizada `contacts_campaign_imports`.
- Inbox settings: `settings/inbox/inbox.routes.js` expõe wizard endereçável: `settings_inbox_new`, `settings_inboxes_page_channel`, `settings_inboxes_add_agents`, `settings_inbox_finish`, `settings_inbox_show`.
- Automação: `settings/automation/automation.routes.js` expõe só `automation_list`; criar/editar são modais dentro da página.
- Autonomia: `autonomia/autonomia.routes.js` expõe `autonomia_agents_index`, `autonomia_agents_builder`, `autonomia_agent_panel`, com gate global + por conta.
- CRM: `crm/crm.routes.js` expõe kanban, calendário, dashboard, SLA, gestão de campanhas e tokens, com `ensureCrmEnabled`.
- Campaigns: `campaigns/campaigns.routes.js` expõe SMS, WhatsApp, WhatsApp API, live chat e e-mail, com redirects e gates.

Conclusão de endereçamento:

- `navigate` é altamente viável com nomes de rota.
- `observe` de superfície é viável por `route.name`, `route.params`, `meta.permissions` e store.
- `open_surface` é viável quando a superfície é rota.
- `open_surface` para modal/drawer exige handler específico ou evento registrado.
- `fill`/`submit` genérico por DOM não é confiável hoje.

## Event bus existente

Arquivos:

- `app/javascript/shared/helpers/mitt.js`
- `app/javascript/shared/constants/busEvents.js`
- `app/javascript/dashboard/composables/emitter.js`

`shared/helpers/mitt.js` exporta um singleton `emitter = mitt()`. `dashboard/composables/emitter.js` adiciona `useEmitter(eventName, callback)` com cleanup em `onBeforeUnmount`.

Contagens:

- 18 eventos em `BUS_EVENTS`.
- 106 ocorrências de `emitter.emit/on/off` em `app/javascript/dashboard`, `app/javascript/shared` e `app/javascript/v3`.

Eventos em `BUS_EVENTS`:

- `SHOW_ALERT`
- `START_NEW_CONVERSATION`
- `FOCUS_CUSTOM_ATTRIBUTE`
- `SCROLL_TO_MESSAGE`
- `MESSAGE_SENT`
- `ON_MESSAGE_LIST_SCROLL`
- `WEBSOCKET_DISCONNECT`
- `WEBSOCKET_RECONNECT`
- `WEBSOCKET_RECONNECT_COMPLETED`
- `TOGGLE_REPLY_TO_MESSAGE`
- `SHOW_TOAST`
- `NEW_CONVERSATION_MODAL`
- `INSERT_INTO_RICH_EDITOR`
- `INSERT_INTO_NORMAL_EDITOR`
- `CRM_FOLLOW_UP_DUE`
- `EMAIL_CAMPAIGN_AI_READY`
- `EMAIL_CAMPAIGN_AI_FAILED`
- `CRM_BOARD_REFETCH`

Eventos adicionais no mesmo `emitter`, fora de `BUS_EVENTS`:

- `newToastMessage`
- `fetch_conversation_stats`
- `clearSearchInput`
- `pause_playing_audio`
- Eventos de teste em `shared/helpers/specs/mitt.spec.js`.

Há também constantes de command bar em `app/javascript/dashboard/helper/commandbar/events.js`:

- `CMD_SWITCH_TAB`
- `CMD_SWITCH_STATUS`
- `CMD_MUTE_CONVERSATION`
- `CMD_UNMUTE_CONVERSATION`
- `CMD_SEND_TRANSCRIPT`
- `CMD_TOGGLE_CONTACT_SIDEBAR`
- `CMD_REOPEN_CONVERSATION`
- `CMD_RESOLVE_CONVERSATION`
- `CMD_SNOOZE_CONVERSATION`
- `CMD_AI_ASSIST`
- `CMD_BULK_ACTION_SNOOZE_CONVERSATION`
- `CMD_BULK_ACTION_REOPEN_CONVERSATION`
- `CMD_BULK_ACTION_RESOLVE_CONVERSATION`
- `CMD_SNOOZE_NOTIFICATION`

Reaproveitamento para UI Action Bus:

- Sim, como transporte local e padrão conhecido.
- Não, como contrato final de operação.

Motivo: o bus atual é global, não tipado, fire-and-forget, sem resposta/erro, sem autorização, sem allowlist, sem idempotência e com eventos misturados entre UX, websocket, command bar, analytics e editor. Para o Operator Agent, o correto é criar um wrapper próprio, por exemplo eventos `OPERATOR_UI_ACTION_REQUESTED` e `OPERATOR_UI_ACTION_RESULT`, ou um composable com `dispatch(action): Promise<Result>`, usando `mitt` por baixo apenas quando fizer sentido.

O melhor precedente é `INSERT_INTO_RICH_EDITOR`: já prova que um agente consegue inserir conteúdo em um editor sem DOM scraping. Mas ele é uma ação isolada, não um registry.

## Formulários e submissão programática

Contagens em `app/javascript/dashboard/components-next` + `app/javascript/dashboard/routes/dashboard`:

- 69 arquivos usam `useVuelidate`.
- 138 ocorrências de `useVuelidate`.
- 91 arquivos têm `<form`, `@submit` ou `type="submit"`.
- 167 ocorrências de `<form`/submit.
- 67 ocorrências de `defineExpose`.
- 768 ocorrências de `v-model`.

Padrões observados:

- Validação local com Vuelidate é comum, por exemplo labels, canned responses, teams, inbox channels, agents, contacts e campaigns.
- Muitos formulários fazem `v$.$touch()`/`v$.$validate()` dentro do próprio componente e só então chamam store/API.
- Componentes novos usam `defineModel`/`v-model` em inputs compostos.
- `Dialog.vue` expõe `open`/`close`, mas não expõe preenchimento/submissão padronizados.
- `AutomationRuleForm.vue` expõe `open`/`close`, valida com `validateAutomation`, `ConditionRow.validate()` e emite `save`.
- `AddAutomationRule.vue` expõe `open`/`close`, mas o estado `automation` é interno ao componente.
- `AutomationRuleForm.vue` usa `woot-input`, `<select>`, `ConditionRow`, `AutomationActionInput`, `SingleSelect`, `MultiSelect`, `WootMessageEditor`.

Conclusão:

- Preencher inputs simples por DOM seria tecnicamente possível, mas frágil e incompleto.
- Selects, multiselects, popovers, editores rich text e formulários compostos precisam de handlers por superfície.
- Para mutações críticas, o Action Bus deve preferir payloads estruturados validados pela própria superfície ou por store/API, com UI observável, não uma sequência de cliques.

## Superfícies analisadas

### Criar inbox Instagram

Arquivos:

- `app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/InboxChannels.vue`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelFactory.vue`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Instagram.vue`
- `app/javascript/dashboard/api/channel/instagramClient.js`
- `app/javascript/dashboard/components/widgets/ChannelItem.vue`

O fluxo é endereçável:

- Ir para `settings_inbox_new`.
- Escolher canal `instagram` muda para `settings_inboxes_page_channel` com `sub_page: 'instagram'`.
- A tela chama `instagramClient.generateAuthorization()`.
- A resposta contém `url` e o componente faz `window.location.href = url`.

Viabilidade:

- `navigate/open_surface`: alta.
- `observe`: média/alta para pré-requisitos (`channel_instagram`, `instagramAppId`, permissões admin).
- `submit`: baixa para completar o fluxo, porque a etapa determinante sai para OAuth externo da Meta.
- O melhor V1 é "abrir autorização do Instagram" e diagnosticar por que não aparece/não pode continuar.

Targets mínimos a adicionar para tornar determinístico:

- `settings-inbox-channel-instagram` em `ChannelItem`/`ChannelSelector`.
- `instagram-connect-button` em `Instagram.vue`.
- Event/handler opcional `operator:inbox:open-channel` que navega direto para `settings_inboxes_page_channel`.

Risco:

- Médio. A rota é estável, mas o fluxo externo não é controlável dentro da UI.

### Criar automação

Arquivos:

- `app/javascript/dashboard/routes/dashboard/settings/automation/automation.routes.js`
- `app/javascript/dashboard/routes/dashboard/settings/automation/Index.vue`
- `app/javascript/dashboard/routes/dashboard/settings/automation/AddAutomationRule.vue`
- `app/javascript/dashboard/routes/dashboard/settings/automation/AutomationRuleForm.vue`
- `app/javascript/dashboard/helper/automationHelper.js`
- `app/javascript/dashboard/helper/validations.js`

O fluxo é parcialmente endereçável:

- `automation_list` abre a página.
- Criar automação é modal local (`AddAutomationRule`) aberto por `openAddPopup`.
- `AddAutomationRule` mantém `automation` local via `useAutomation(START_VALUE)`.
- `AutomationRuleForm` valida e emite payload para `submitAutomation`, que faz store dispatch `automations/create`.

Viabilidade:

- `navigate`: alta.
- `open_surface`: média; precisa handler/evento para abrir o modal.
- `fill`: média se for handler estruturado; baixa se for DOM genérico.
- `submit`: média; o payload pode ser validado por `validateAutomation` e `generateAutomationPayload`.

Targets/handlers mínimos:

- `automation-create-button`.
- `automation-dialog`.
- `automation-name-input`.
- `automation-description-input`.
- `automation-event-select`.
- Targets por linha de condição/action se insistir em fill visual.
- Melhor: handler `operator:create_automation(payload)` que abre modal com o draft, mostra highlight/resumo e submete após confirmação.

Risco:

- Médio/alto se baseado em DOM, porque usa componentes compostos.
- Médio se baseado em payload estruturado, porque toca pouco no upstream: `Index.vue`, `AddAutomationRule.vue` e/ou um registro local.

### Importar base de campanha

Arquivos:

- `app/javascript/dashboard/routes/dashboard/contacts/routes.js`
- `app/javascript/dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue`
- `app/javascript/dashboard/components-next/Contacts/CampaignImport/CampaignImportDialog.vue`
- `app/javascript/dashboard/routes/dashboard/contacts/pages/CampaignImportHistory.vue`

Embora não esteja no exemplo do PRD, é uma ótima superfície piloto porque é código customizado do fork.

O fluxo é parcialmente endereçável:

- Histórico é rota: `contacts_campaign_imports`.
- Dialog de upload é modal aberto a partir do header de contatos.
- Gate já existe por `window.globalConfig?.CAMPAIGN_IMPORT_ENABLED === 'true'` e admin.

Viabilidade:

- `navigate`: alta para histórico.
- `open_surface`: média/alta com um evento local.
- `fill`: alta para `campaignName` e `batchCount`; arquivo ainda exige File API/input real.
- `submit`: média; upload programático precisa tratamento explícito e confirmação.

Targets mínimos:

- `campaign-import-open-button`.
- `campaign-import-history-button`.
- `campaign-import-dialog`.
- `campaign-import-name-input`.
- `campaign-import-batch-count-input`.
- `campaign-import-file-input`.
- `campaign-import-submit-button`.
- Targets para ações de histórico: confirmar, desfazer labels, baixar CSVs.

Risco:

- Baixo. É superfície própria, com baixo churn upstream.

### Autonomia Agents

Arquivos:

- `app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js`
- `app/javascript/dashboard/routes/dashboard/autonomia/pages/*`
- `app/javascript/dashboard/routes/dashboard/autonomia/components/*`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

Rotas próprias:

- `autonomia_agents_index`
- `autonomia_agents_builder`
- `autonomia_agent_panel`

Gate próprio:

- ENV/globalConfig `AUTONOMIA_AGENTS_ENABLED`.
- Conta com `autonomia_agents_enabled`.
- `meta.permissions: ['administrator']`.

Viabilidade:

- Alta para piloto de registry, porque a área é customizada e já isolada.
- Baixo risco de churn upstream.
- Boa para ações `navigate`, `observe`, `highlight`, `open_surface`.

Risco:

- Baixo/médio. O risco é mais de produto do que técnico.

## UI Registry proposto

O registry deve ser pequeno e allowlisted. Não deve tentar mapear o app inteiro.

Modelo mínimo por superfície:

```js
{
  id: 'settings.automation.list',
  route: { name: 'automation_list' },
  permissions: ['administrator'],
  featureFlag: 'automations',
  env: [],
  targets: {
    createButton: '[data-testid="automation-create-button"]',
  },
  actions: {
    navigate: true,
    openCreate: 'operator:automation:open-create',
    create: 'operator:automation:create',
  },
  observe: ['route', 'permissions', 'store.automations/getAutomations']
}
```

Ações estruturadas:

- `navigate(surfaceId, params, query)`
- `open_surface(surfaceId, intent)`
- `highlight(surfaceId, targetId)`
- `fill(surfaceId, payload)`
- `submit(surfaceId, payload)`
- `observe(surfaceId)`

Regras técnicas:

- Resolver permissão a partir de `router.resolve(...).meta.permissions` e `usePolicy`.
- Nunca confiar só no frontend para autorização; toda mutação deve continuar passando por API/backend/Pundit.
- Preferir route names e store/API existentes a seletores.
- Usar `data-testid` só como alvo de highlight/foco/click em superfícies permitidas.
- Retornar resultado estruturado com `ok`, `error`, `surface`, `route`, `changed`, `next`.
- Registrar handlers perto do código customizado Autonom.ia quando possível.

## Custo de manutenção vs churn upstream

Cobertura ampla do Chatwoot é cara e frágil:

- 4.870 arquivos em `app/javascript`.
- 474 arquivos só em `dashboard/routes/dashboard`.
- Apenas 17 `data-testid`.
- Muitas telas de settings usam componentes upstream que podem mudar em atualizações.

Custo recomendado:

- Criar infraestrutura registry/bus em código próprio: 2 a 4 dias.
- Por superfície simples roteável: 0,5 a 1 dia.
- Por modal/form composto: 1 a 3 dias.
- Automação completa com payload estruturado: 3 a 5 dias.
- Inbox Instagram até "abrir OAuth e diagnosticar": 1 a 2 dias.
- Inbox Instagram E2E passando por OAuth externo: não recomendar como V1.
- Campanha import, por ser custom: 1 a 2 dias para abrir/focar/preencher/submeter com targets estáveis.

Estratégia para sobreviver a updates do Chatwoot:

- Não espalhar registry em arquivos upstream.
- Criar um módulo próprio, por exemplo `app/javascript/dashboard/autonomia/operator/*` ou `app/javascript/dashboard/operator/*`.
- Tocar upstream apenas em pontos mínimos:
  - `Dashboard.vue` para montar o listener/global controller, se necessário.
  - componentes específicos para `data-testid`/handler de superfície.
  - nada em rotas genéricas se for possível registrar por import custom.
- Para telas upstream, limitar mudanças a 3-8 atributos `data-testid` por superfície.
- Para telas customizadas, aceitar mais instrumentação.

## Recomendação de ordem

1. `navigate` + `observe` global por route registry.
   - Baixo risco.
   - Usa 142 nomes de rota já existentes.
   - Entrega descoberta/navegação determinística antes de mutação.

2. Piloto em superfície customizada: `contacts_campaign_imports` / Campaign Import.
   - Baixo churn.
   - Gate e permissão já existem.
   - Bom para provar `open_surface`, `highlight`, `fill`, `submit`, `observe`.

3. Piloto em `automation_list` para criar automação por payload estruturado.
   - Alto valor operacional.
   - Evitar DOM genérico.
   - Exige handler específico para abrir/preencher/submeter modal.

4. Inbox Instagram só como navegação + diagnóstico + iniciar OAuth.
   - Útil para suporte operacional.
   - Não vender como ação concluída porque depende da Meta e do usuário.

5. Expandir para Autonomia Agents.
   - Área própria, baixo churn e coerente com o agente operacional.

## Veredito

Pilar 2 é viável com abordagem incremental e determinística.

Não é viável, com segurança aceitável, tentar operar o Chatwoot inteiro por seletores DOM no estado atual. A falta de `data-testid`, o uso pesado de modais locais e componentes compostos fariam o sistema quebrar em upgrades.

O desenho recomendado é:

- UI Registry allowlisted por superfície.
- `mitt` reutilizado apenas como transporte local.
- Rotas nomeadas como base de navegação.
- Permissões/feature flags derivadas de `meta`, `usePolicy`, globalConfig e gates por conta.
- Handlers estruturados para formulários importantes.
- Poucos `data-testid` adicionados nas primeiras superfícies.

Primeiras superfícies recomendadas:

- Campaign Import: 1-2 dias, baixo risco, código próprio.
- Criar automação: 3-5 dias, valor alto, risco médio, requer payload estruturado.
- Inbox Instagram: 1-2 dias para abrir/diagnosticar/iniciar OAuth, não para completar E2E.

