# Plano de Ação — CRM Kanban (Chatwoot fork pt_BR, conn234)

## DECISÕES QUE PRECISO DE VOCÊ

Antes de implementar, preciso de 3 decisões de produto. As demais correções são bugs e seguem independente da sua resposta.

1. **pt_BR no CRM** — O repo tem regra "só en"; mas a instância roda em pt_BR e o CRM aparece em inglês para o usuário (tokens, n8n, criação de tokens). **Recomendo traduzir** o namespace CRM-custom (crm.json, integrations.json) para pt_BR como exceção à regra, já que é fork single-tenant sem comunidade de tradução. **Pergunta: aprova manter pt_BR para os strings CRM-custom (e aceitar o custo de manter 2 arquivos de locale em sincronia)?**

2. **Token escopado do n8n** — Existe um sistema de token CRM-only, revogável (inbound n8n→CRM) além do webhook (outbound CRM→n8n). **Recomendo manter** o token escopado (least-privilege; um token de usuário vazaria a conta inteira). Opcional: oferecer 1-2 "bundles" de escopo pré-selecionados para simplificar. **Pergunta: mantém o token escopado como está, ou quer também os bundles de escopo prontos?**

3. **Card n8n vs Webhooks nativos** — O card n8n não é um motor concorrente; é um wizard guiado por cima dos Webhooks nativos da conta. **Recomendo manter os dois** e deixar a relação explícita na copy ("powered by account Webhooks"). **Pergunta: mantém o card n8n como recipe guiado (recomendado) ou prefere removê-lo e deixar só Webhooks crus?**

4. **Painel de IA para perfis sem permissão** (I3) — Seats sem `crm_manage_ai` conseguem ver o toggle mas o save dá 403. **Recomendo esconder** o painel desses perfis. **Pergunta: esconder o painel de quem não tem `crm_manage_ai`, ou mostrar e exibir o erro 403 real?**

---

## 1. Tabela-resumo

| ID | Problema (1 linha) | Tipo | Causa-raiz curta | Esforço | Deploy |
|----|--------------------|------|------------------|---------|--------|
| I1 | "Concluir" do popup de follow-up não some (clica 40x, nada) | BUG | `completeReminder` sem try/catch + API account-scoped chama conta errada (404 cross-account) | S | frontend |
| I2 | Card mostra nome/telefone do contato duplicado | BUG | `derived_title` e `contactLabel` usam a mesma fonte (contato) | S | frontend |
| I3 | Toggle "Mover automaticamente" parece não persistir | BOTH | Painel nunca re-sincroniza form do servidor; save rejeitado (gate EE) deixa toggle visualmente ON | S | frontend |
| I4 | Seção de template some em auto-send com data futura | BOTH | `requiresTemplateNow` usa janela em `Time.current`, não em `dueAt` | M | both |
| I5 | Card n8n com logo ChatGPT (ícone errado/sem contraste) + parece redundante | BOTH | PNGs são cópia do placeholder `crm_kanban_ai`; card é wizard sobre Webhooks nativos | S | frontend |
| I6 | Página de tokens em inglês, sem cancelar/voltar, labels = chave crua | BOTH | Falta subtree `CRM_INTEGRATION_TOKENS` no pt_BR; sem botão Cancelar/back; label imprime `{{ scope }}` cru | S | frontend |
| I7 | Botão "Conectar" do n8n morto (href vazio) | BOTH | Card informativo renderizado via `Integration.vue` que assume ciclo connect/disconnect inexistente | S | frontend |
| I8 | Kanban IA mostra "Desconectado" mesmo funcionando | BOTH | `enabled?` checa só hook; IA usa fallback de chave de sistema (`CAPTAIN_OPEN_AI_API_KEY`) | S | backend |

---

## 2. Detalhe por ponto

### I1 — Popup "Concluir" no-op (fica preso na tela)
**Causa-raiz:** `useCrmFollowUpReminders.js:47-50` faz `await completeFollowUp(id)` e só depois `dequeueReminder()`, sem try/catch — se rejeitar, o popup nunca sai. A API é `accountScoped:true` (`api/crmKanban.js:6`), então chama `/accounts/{conta_da_rota_atual}/...`, mas o popup é global/cross-account alimentado por broadcast com `account_id` próprio (`broadcaster.rb:33-46`). Reminder da conta A com agente na conta B → `policy_scope(...).find` (`follow_ups_controller.rb:80-83`) → 404 → await rejeita → popup eterno. Caso secundário: item já concluído retorna 200 sem mudança (`follow_ups_controller.rb:173-181`).

**Correção (fazer A + B):**
- **A (rede de segurança):** envolver `completeReminder` e `dismissReminder` em `try { await... } finally { dequeueReminder() }` — o popup some no clique independentemente do resultado. Manter `seenIds`.
- **B (correção de raiz):** usar o `account_id` do reminder (já em `normalizeReminder`, linhas 15-21) na chamada — variante account-explicit só para o popup: `POST /api/v1/accounts/${reminder.account_id}/crm/follow_ups/${id}/complete`.

Não é decisão de produto. pt_BR de "Concluir"/"Dispensar" já existe (`pt_BR/crm.json:466-467`).

### I2 — Nome do contato duplicado no card
**Causa-raiz:** `creator.rb:41,47-52` backfilla `title` com `contact.name || contact.phone_number`; `CrmKanbanCard.vue:42-48` deriva `contactLabel` da mesma fonte. Renderiza as duas linhas (`:165-176`) idênticas quando não há título custom.

**Correção (frontend-only, `CrmKanbanCard.vue`):** computed `showContactLine = Boolean(contactLabel.value) && contactLabel.value !== props.card.title` e `v-if="showContactLine"` na linha de contato. Não mexer no `derived_title` (manteria títulos em branco). Não é decisão de produto.

### I3 — Toggle auto_move "não persiste"
**Causa-raiz:** O backend persiste corretamente (`settings_updater.rb:19-27`, `settings_presenter.rb:11`, spec `ai_settings_spec.rb:37-51` prova round-trip). O defeito real: `CrmAiSettingsPanel.vue:64-91` nunca re-sincroniza `form` com a resposta; em save rejeitado pelo gate EE `manage_ai?` (`pipeline_policy.rb:24-26`), o toggle fica visualmente ON sem ter persistido.

**Correção:**
- **#1 (incondicional):** no `saveSettings()` aplicar a resposta de volta no form: `form.autoMoveEnabled = response.data.payload?.auto_move_enabled === true` (idem `enabled`/`staleHours`). O checkbox passa a refletir o que persistiu.
- **#2 (decisão — ver DECISÃO 4):** esconder o painel de seats sem `crm_manage_ai` em `CrmPipelineDrawer.vue:338-342`, reusando o check `canManagePipelines`. Manter a policy EE como está.

### I4 — Template some em auto-send com data futura
**Causa-raiz:** `CrmCardDrawer.vue:158-160` `requiresTemplateNow` espelha um flag calculado em `Time.current` (`messaging_window.rb:24-38`), não no `dueAt` escolhido. Auto-send futuro nunca mostra/exige template e falha no envio.

**Correção:**
- **PART1 (agora):** adicionar arg opcional `at` em `MessagingWindow` e passar `due_at`; watcher no `dueAt` no frontend re-busca a janela para mostrar a UI de template quando o envio cai fora da janela; `AutoSendValidator` avalia em `follow_up.due_at`.
- **PART2 (decisão — motor de template):** **Recomendo** reusar o motor de template nativo (`whatsapp_api_message_templates`) para inboxes WhatsApp nativos e manter a tabela custom só para Channel Api. **Pergunta: aprova reusar o engine nativo para WhatsApp oficial (recomendado) em vez de manter tabela custom para todos?**

### I5 — Ícone n8n + redundância aparente
**Causa-raiz (ícone, bug):** `crm_n8n.png`/`crm_n8n-dark.png` são cópia byte-a-byte do placeholder `crm_kanban_ai` (md5 confere) = logo swirl do ChatGPT, branco-no-transparente no dark = quase invisível. O campo `logo:` do `apps.yml` e a prop `:integration-logo` são **dead code** — `Integration.vue:72-77` monta o src por `integrationId`, ignora a prop. Só substituir os PNGs resolve.
**Causa-raiz (redundância, decisão):** `CrmN8n.vue:33-42,90-105` é wizard de deep-link sobre os Webhooks nativos (`webhook.rb:39-49` CRM_WEBHOOK_EVENTS, entregues por `crm_delivery_job.rb`). Não é motor concorrente.

**Correção:** substituir os 2 PNGs pela marca real do n8n (512x512 RGBA; dark = glifo claro no transparente). Adicionar 1 linha de copy em `integrations.json` esclarecendo "powered by account Webhooks". pt_BR do bloco `CRM_N8N` (ver DECISÃO 1). **Ver DECISÕES 1 e 3.**

### I6 — Página de tokens (inglês, sem cancelar/voltar, label crua)
**Causa-raiz:** (1) `pt_BR/crm.json` só tem `CRM_KANBAN`, falta `CRM_INTEGRATION_TOKENS`; i18n sem `fallbackLocale` explícito (`dashboard.js:36-40`) cai pra 'en'. (2) Rota full-page (`crm.routes.js:51-56`); form inline sem Cancelar (`resetForm()` existe em `:84-87`, só chamado pós-criação) e header sem back (`:176-183`). (3) `CrmIntegrationTokensPage.vue:283` imprime `{{ scope }}` cru como label e checkbox nativo (`:275-280`).

**Correção:** (A) bloco `CRM_INTEGRATION_TOKENS` em pt_BR espelhando en — **ver DECISÃO 1**. (B) Botão Cancelar chamando `resetForm()`; (C) Botão back (`i-lucide-arrow-left` + `router.back()`) no header; (D) `scopeLabel(scope)` como label primário, `{{ scope }}` como tag mono/muted. B/C/D são bugs/UX, vão independentemente.

### I7 — Botão "Conectar" do n8n morto
**Causa-raiz:** `crm_n8n` é card informativo mas renderizado via `Integration.vue` que assume connect/disconnect. `enabled?` (`app.rb:87-96`) cai em `account.hooks.exists?` — nunca há hook — logo renderiza branch Connect (`:118-128`) como anchor `href=integrationAction`, e `CrmN8n.vue:44-46` devolve string vazia → href vazio → clique não faz nada. Os CTAs reais (TOKENS_CTA, WEBHOOK_CTA) estão mais abaixo.

**Correção (preferida A):** em `CrmN8n.vue` remover o bloco `Integration` do topo (`:70-77`) e o computed `integrationAction` (`:44-46`), trocando por header simples (logo+nome+descrição); os 2 CTAs já existem abaixo. pt_BR do bloco `CRM_N8N` (DECISÃO 1). Não tocar `app.rb`/backends de token e webhook (corretos). **Ver DECISÃO 2** (token) e **1** (pt_BR).

### I8 — Kanban IA "Desconectado"
**Causa-raiz:** `app.rb:87-96` não tem branch `crm_kanban_ai`, cai no `else account.hooks.exists?`. Mas `CredentialResolver#resolve` (`credential_resolver.rb:8-12,35-45`) aceita fallback de chave de sistema (`CAPTAIN_OPEN_AI_API_KEY`), então a IA funciona sem hook enquanto o card lê "Desconectado".

**Correção (backend, 1 linha):** branch em `App#enabled?` para `crm_kanban_ai` retornando `CredentialResolver.new(account: account).configured?`. Spec: 3 casos (só sistema / hook desabilitado / hook válido). Opcional: mostrar a fonte (sistema vs conta) na tela de config. pt_BR já traduzido.

---

## 3. Agrupamento por onda de execução

**Gates obrigatórios em toda onda:** `eager_load` (smoke de boot do Rails p/ qualquer mudança backend) + teste visual (Kanban, drawer, popup, página de tokens, lista de integrações) antes de promover imagem.

### Onda A — Frontend-only, paralelizável (uma branch, um deploy de assets/vite)
Pode ir tudo junto, baixo risco, sem migração:
- **I2** dedupe da linha de contato (`CrmKanbanCard.vue`)
- **I5-ícone** trocar os 2 PNGs `crm_n8n*` pela marca real do n8n + copy "powered by Webhooks"
- **I6-UX** Cancelar + back + label de escopo (`CrmIntegrationTokensPage.vue`)
- **I7** remover bloco Integration morto do `CrmN8n.vue` (botão Conectar)
- **I3-#1** re-sincronizar form com resposta no `CrmAiSettingsPanel.vue` (parte incondicional)
- **i18n pt_BR** (se DECISÃO 1 = sim): blocos `CRM_INTEGRATION_TOKENS`, `CRM_N8N`, demais CRM-custom em pt_BR — gate extra: paridade 1:1 de chaves com en (chave faltando → cai em inglês).

Gate: teste visual em pt_BR confirmando ausência de inglês, ícone n8n visível no dark, sem linha de contato duplicada.

### Onda B — Lógica/comportamento (revisar com cuidado, frontend + backend)
Sequencial após A (ou paralelo se branches isoladas), exige testes de comportamento:
- **I1** try/finally + chamada account-explicit no popup (frontend) — testar cross-account e no-op de item já concluído.
- **I4-PART1** `MessagingWindow(at:)` + watcher `dueAt` + `AutoSendValidator` em `due_at` (backend + frontend) — gate `eager_load`; testar auto-send futuro fora da janela.
- **I3-#2** (se DECISÃO 4 = esconder): gate de visibilidade do painel IA em `CrmPipelineDrawer.vue` — regression: admin e agente comum ainda veem e salvam.

### Onda C — Status da integração (backend isolado)
- **I8** branch `crm_kanban_ai` em `App#enabled?` usando `CredentialResolver` — 1 linha + spec (3 casos). Gate `eager_load` + verificar badge "Conectado" com chave de sistema e sem hook.

### Pós-decisão (não bloqueiam as ondas acima)
- **I4-PART2** (engine de template nativo) — depende da resposta da Pergunta em I4; é refactor M, melhor isolar em onda própria.
- **I5/I7 redundância n8n** — só copy/produto, depende das DECISÕES 2 e 3; sem código além da linha de copy.
---

## DECISÕES TRAVADAS (usuário, 2026-06-10)
- **D1 idioma:** seguir o i18n nativo do Chatwoot → adicionar **pt_BR** dos textos CRM-custom (espelhando en), gate de paridade de chaves. A UI do CRM passa a respeitar o idioma da instância.
- **D2 token:** manter o token escopado como está.
- **D3 card n8n:** manter como assistente guiado (corrigir ícone/botão/copy "powered by Webhooks").
- **D4 painel IA sem permissão:** esconder de seats sem `crm_manage_ai`.
- **I4 template:** reusar o motor nativo de templates WhatsApp (whatsapp_api_message_templates) nas inboxes WhatsApp oficiais; tabela custom só p/ Channel API.

## EXECUÇÃO (orquestração + review, por onda)
- **Onda A (frontend, paralela):** I2 dedupe contato · I5 ícone n8n + copy · I6 cancelar/voltar/label + pt_BR (CRM_INTEGRATION_TOKENS/CRM_N8N + demais CRM) · I7 remover bloco Integration morto · I3#1 re-sync do form.
- **Onda B (lógica):** I1 try/finally + chamada account-explicit · I4 PART1 (janela por dueAt) + PART2 (motor nativo de template) · I3#2 esconder painel IA.
- **Onda C (backend):** I8 status "Conectado" via CredentialResolver.
- Gates por onda: eager_load (backend) + teste visual real (Kanban/drawer/popup/tokens/integrações) em pt_BR.
