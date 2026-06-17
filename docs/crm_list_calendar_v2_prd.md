# PRD — CRM Kanban Pro: Lista & Calendário (v2 "versão final")

> **Status:** proposta (não iniciada). Documento de produto + UX + especificação técnica.
> **Contexto:** fork Chatwoot v4.14.1 EE em `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`, deploy Docker Swarm single-node, host `https://chat.autonomia.site`. Produção atual: `conn6`. Conta de teste: **6** (Seguro Viagem, pipeline 9).
> **Por que existe:** Lista e Calendário foram entregues como **MVP** na PR10 e nunca tiveram uma versão "final" especificada. Este PRD define essa versão, ancorada em (1) pesquisa das melhores práticas de CRM 2024–2026 e (2) na identidade real do Chatwoot (components-next, tokens `n-*`, libs já no bundle, contratos de backend já existentes).
> **Âncora do roadmap:** [[crm_roadmap_status]] (`docs/crm_roadmap_status.md`).

---

## 0. Objetivo e princípios

**Objetivo.** Transformar a Lista (hoje uma tabela estática de 6 colunas, sem sort/edição) e o Calendário (hoje uma **lista cronológica plana**, não uma grade) em duas superfícies de trabalho de classe mundial, no padrão visual e de interação do Chatwoot, **sem dependência nova** e **sem violar o "Tailwind only / no custom CSS"**.

**Princípios de design (não negociáveis):**
1. **Identidade Chatwoot primeiro.** Só components-next + tokens `n-*` + ícones `i-lucide-*`. Nada de CSS custom/scoped/inline (exceção já existente: `:style` para a cor dinâmica do estágio).
2. **Reuso > reinvenção.** Lista sobre `@tanstack/vue-table` v8 (já usado em `dashboard/components/table/Table.vue` e nos relatórios). Calendário com `date-fns`/`date-fns-tz` (já no bundle) + `vue-datepicker-next` para o mini-date-picker.
3. **Backend já entrega quase tudo.** `Crm::Cards::FilterQuery`, `Crm::Cards::CalendarQuery` e o `CardPayloadBuilder` já expõem os dados; os deltas de backend são pequenos e listados em cada parte.
4. **pt_BR + en com paridade 1:1.** Override consciente do CLAUDE.md "só en" — a instância roda pt_BR (decisão travada no roadmap).
5. **Zero regressão.** Kanban, drawer, filtros e realtime atuais continuam idênticos. Lista e Calendário são re-skins/upgrades das views existentes, atrás do mesmo `viewMode`.
6. **Gates de sempre:** `eager_load` se mexer `.rb`, teste visual real (SSO + Playwright) em pt_BR, deploy só com OK explícito, rollback pronto.

**Antimetas (fora de escopo nesta v2):** colunas/campos customizados pelo usuário (custom fields), automações novas, mudar o motor do Kanban, billing, multi-moeda real (somatórios assumem moeda única por conta — herdado da PR14).

---

## 1. Onde estamos (o gap, resumido)

| Superfície | MVP hoje | Arquivos |
|---|---|---|
| **Lista** | `<div grid>` com 6 colunas fixas (Card, Estágio, Dono, Inbox, Follow-up, Valor). Sem ordenar, sem editar, sem seleção, sem paginação visível (busca 75 de uma vez). Filtros já ricos (compartilhados com o Kanban). | `CrmKanbanPage.vue:1413-1490` |
| **Calendário** | Lista vertical de eventos (`follow_up_*` + `expected_close`), janela fixa −30/+90 dias. **Não é grade.** Sem navegar mês, sem arrastar, sem criar. | `CrmKanbanPage.vue:1492-1548` |

Backend já disponível e reaproveitável:
- `Crm::Cards::FilterQuery` (lista) — honra `pipeline_id, inbox_id, owner_id, priority, search, follow_up_status, result(won/lost/archived), standalone, stage_ids, team_id, value_min/max, stale_days, responsible_kind, ai_pending`. **Ordena fixo por `updated_at desc`** (delta: aceitar `sort`).
- `Crm::Cards::CalendarQuery` + `calendar_controller` — eventos `expected_close` + `follow_up_{reminder_only|snooze_conversation|auto_send_message}`, params `from/to/pipeline_id/owner_id`, limit clamp [1,500].
- `CardPayloadBuilder` — `value_cents, currency, priority, score, status, next_follow_up_at, last_message_at, entered_stage_at, ai_suggestion, contact{}, owner{}, responsible{type,id,name}, inbox{}, conversation{display_id,assignee}`.

---

## 2. Inventário de identidade (o que existe vs. o que construir)

**components-next prontos:** `Button` (variant/color/size/icon/isLoading), `Input` (text/number, messageType), `Popover` (align, `.show()/.hide()`), `Spinner`, `Dialog`/`ConfirmModal`, `Checkbox`, `ComboBox` (busca client/API), `SelectMenu`, `TabBar` (tabs com count), `PaginationFooter` (currentPage/totalItems/itemsPerPage), `BaseTable`+`BaseTableRow`+`BaseTableCell`, `Avatar`.

**Libs já no bundle:** `@tanstack/vue-table@8` (headless table), `date-fns@2.21` + `date-fns-tz`, `vue-datepicker-next@1`.

**A construir (não existe em components-next):** `Tag/Chip` (chips de filtro hoje são inline), célula de **edição inline**, **barra de ações em massa** (floating), **menu de colunas** (show/hide/reorder), **grade de calendário** (mês/semana/dia) + **popover de evento**, cabeçalho de coluna **ordenável**. (Tooltip: usar `title` nativo / texto de ajuda no MVP.)

**Tokens em uso (manter):** `n-slate-{9..12}` (texto/neutro), `n-brand` (ação primária), `n-teal-{9..11}` (sucesso/pendente), `n-ruby-{9..11}` (erro/atrasado), `n-amber-9` (aviso), `n-surface-{1,2}`, `n-alpha-black2`/`n-alpha-2/3` (overlay/hover), `outline-n-weak` (bordas). Ícones `i-lucide-*`. Datas via `Intl.DateTimeFormat('pt-BR')` / `timeHelper.js`; moeda via `Intl.NumberFormat('pt-BR', {currency})`.

---

# PARTE A — LISTA / TABELA (v2)

Ancorada em **Linear** (interação/teclado/multi-seleção) e **Attio/Notion/Airtable** (modelo de Views + edição inline + estado por-view), validada por HubSpot/Pipedrive/Salesforce/Folk (pills de estágio, avatar de dono, moeda, bulk-edit, visibilidade por time).

## A0. Arquitetura: a tabela é **uma View** salva
O maior padrão estrutural dos melhores produtos: a tabela não é "a página", é **uma View** do objeto (cards do funil). Modelo: `View = { pipeline, columns[], filters[], sort[], groupBy, density, visibility }`.
- **MVP:** 1 view default por funil + preferências de coluna por usuário (localStorage).
- **Full:** Views nomeadas, salváveis e compartilháveis (Private / Time / Custom — modelo HubSpot), em uma faixa de abas estilo Attio/Notion (reusar `TabBar`).

## A1. Sistema de colunas
- **MVP:** mostrar/ocultar, reordenar (drag no header), redimensionar, **1ª coluna (título) congelada** (sticky), conjunto default sensato por funil. Colunas candidatas: Card (título+contato), Estágio (pill colorida), Dono (avatar), Responsável (agente/bot), Valor (R$), Status, Próximo follow-up, Última atividade (relativa), Inbox, Prioridade, Score IA, Conversa (chip deep-link).
- **Full:** congelar N colunas (cap ~3), toggle de densidade (compacto/confortável), estado de coluna por-view, agregados no topo da coluna (Σ valor).
- **Como:** `@tanstack/vue-table` `columnVisibility` + `columnOrder` + `columnSizing` (headless); menu de colunas num `Popover` com `Checkbox`. Sticky via `position: sticky` utilitário do Tailwind (sem CSS custom).

## A2. Edição inline
- **MVP:** **single-click** edita na própria célula: Valor (input moeda), Dono (picker avatar via `ComboBox`), Estágio (select colorido), Status (won/lost/open), Próximo follow-up (date picker). **Update otimista** com rollback + toast no erro. Enter confirma, Esc cancela. Tudo que é rico/relacional **abre o drawer** (já existe).
- **Full:** travessia Tab/Enter entre células, navegação por setas, "aplicar a N selecionados" (mass-inline — Pipedrive/Salesforce).
- **Backend delta:** mover/estágio já é via `#move`; valor/dono/status/follow-up via `PATCH /crm/cards/:id` (já aceita esses campos não-estágio). Confirmar que `value_source` vira `human` ao editar valor (trava o autofill da IA — regra travada na PR14).

## A3. Ordenação & agrupamento
- **MVP:** sort single clicando no header (asc/desc/none), com indicador; group-by **Estágio** e **Dono** com headers colapsáveis mostrando **contagem + Σ valor**.
- **Full:** multi-sort com prioridade reordenável, sub-grupos, escolha de agregação por grupo (sum/avg/count), estado de colapso persistido.
- **Backend delta:** `FilterQuery` passa a aceitar `sort` (ex.: `value_cents`, `next_follow_up_at`, `last_activity_at`, `title`, `entered_stage_at`) + `direction`. Agregação Σ por grupo: endpoint leve de rollup ou cálculo client se a página couber. (Hoje ordena fixo `updated_at desc`.)

## A4. Ações em massa
- **MVP:** checkbox por linha + header (seleciona página) → **barra flutuante** (fixada embaixo) com contagem e: **Mover estágio, Atribuir dono, Mudar status, Excluir**. Toast de undo em ações destrutivas.
- **Full:** "selecionar todos os N do filtro" (server-side), multi-seleção por teclado (X / Shift-range / Cmd+A / Esc — modelo Linear), bulk-edit de qualquer campo via painel.
- **Backend delta:** endpoint de mutação em lote `POST /crm/cards/bulk` `{ ids[], action: move|assign|status|delete, payload }` (transacional, respeita Pundit/scope, idempotente). Reusa a infra de webhooks/atividades já existente.

## A5. Filtragem (reusar + evoluir)
- O conjunto de filtros do MVP **já é forte** e compartilhado com o Kanban. Manter.
- **MVP+:** extrair os chips para um componente `CrmFilterChip` reutilizável; mostrar contagem por chip quando barato.
- **Full:** construtor de filtro aninhado AND/OR (modelo Notion 3 camadas) + salvar como View nomeada (ver A0).

## A6. Afford­ances de linha
- Dono = `Avatar` (nome no hover); Estágio/Status = pill colorida; Valor = `R$ 12.500` formatado; datas = **relativas** ("há 3d", "em 2 dias") com absoluta no `title`; **follow-up atrasado = vermelho** (já existe `followUpBadgeClass`); conversa = chip que faz deep-link.
- **Clique:** célula edita; título/affordance dedicada **abre o drawer** (mantém contexto da lista — padrão moderno Attio/Notion).
- **Full:** cluster de quick-actions no hover (abrir, registrar atividade, `…`), paginação prev/next por teclado dentro do drawer percorrendo o set filtrado.

## A7. Performance
- **MVP:** filter/sort/paginate server-side, header sticky, **skeleton rows** no load (primeiras ~5 linhas), `PaginationFooter` (já existe). `RESULTS_PER_PAGE=25`, max 100.
- **Full:** **virtualização** de linhas (TanStack row virtualizer), scroll infinito com prefetch (~3× página), cache local otimista, restauração de scroll ao voltar do drawer.

## A8. Estados (vazio / load / erro)
- **MVP:** skeleton no 1º load; **dois vazios distintos** — "nenhum card ainda" (CTA criar) vs "nenhum resultado para esses filtros" (CTA limpar filtros); erro com mensagem + **Tentar de novo**.
- **Full:** barra de progresso não-bloqueante no refetch, retry por célula, ilustração no vazio.

## A9. Teclado & acessibilidade
- **MVP:** ↑/↓ navega linha, Enter abre, Esc limpa seleção; `role="grid"` + roving `tabindex` + `aria-label`; integrar à command palette se houver (Cmd+K).
- **Full:** j/k + x-select + Shift-range (Linear), navegação por setas em nível de célula, Home/End/Ctrl combos, validação com leitor de tela.

## A10. Mobile / responsivo
- **MVP:** abaixo do breakpoint, linhas viram **cards** (título como header + 2–4 campos críticos), colunas prioritárias, tap abre detalhe; barra de bulk em ícones.
- **Full:** campos do card configuráveis, swipe quick-actions, fallback de scroll horizontal com 1ª coluna congelada no tablet.

---

# PARTE B — CALENDÁRIO (v2)

> **Achado-chave do domínio:** os 3 tipos de item **não são simétricos** e isso guia quase tudo:
> - **Follow-up (lembrete)** → comporta-se como *tarefa*; muitas vezes "all-day", pode ficar **atrasado**, precisa ser reagendável.
> - **WhatsApp agendado** → instante preciso, *system-owned*; arrastável p/ reagendar mas **resize não faz sentido** (duração zero) e **não pode ir pro passado**.
> - **Previsão de fechamento (`expected_close`)** → *marco* de um deal, não um "evento"; arrastar deve **mutar a data do deal com confirmação**, nunca redimensionar.
>
> Tratar como **3 "calendários" sobreponíveis** (overlays com toggle), não um stream único.

## B1. Modos de visualização
- **MVP:** **Mês (grade)** + **Agenda/Lista** (a agenda reaproveita o feed cronológico atual e é o fallback mobile).
- **Full:** **Semana** e **Dia** (time-grid com linha "now" e faixa all-day no topo). Persistir o último modo escolhido.
- **Default:** Mês para visão de gestor/forecast; Semana (quando existir) para o rep individual.

## B2. Navegação
- **MVP:** botão **Hoje** + chevrons ‹ › + título do período; clicar num dia do mês entra no Dia/Agenda daquele dia. **Mini-calendário** (`vue-datepicker-next`) para "ir para data".
- **Full:** atalhos de teclado (T = hoje, setas, números p/ trocar view).

## B3. Renderização de eventos + cor
- **Mês:** evento como **pill** (dot colorido + título truncado, ~13px, 1 linha); estouro = **"+N mais"** → `Popover` listando o resto (padrão universal). Dia de hoje destacado.
- **Cor = por TIPO** (lembrete / WhatsApp / fechamento) como default — os 3 se comportam diferente; **por dono** como modo secundário (toggle, p/ gestor). Sempre com **ícone** junto (sino / `i-lucide-message-circle` / `i-lucide-target`) p/ sobreviver a daltonismo e à degradação mobile (dot-only). Evitar cor por estágio/status (muitos valores).
- **Atrasado:** tratamento vermelho por cima da cor do tipo (ver B7).
- **Full (semana/dia):** blocos proporcionais à duração, faixa all-day, empilhamento de sobreposição.

## B4. Drag & drop (regras por tipo)
- **MVP:** arrastar p/ reagendar dia (no Mês), update otimista + undo. **Bloquear drop no passado** p/ WhatsApp; **completados/enviados** ficam read-only/dimmed.
- **`expected_close`:** drag abre **confirm** ("Mover previsão de fechamento do Deal X para 20/jun?") — muta campo do deal.
- **Full:** drag+time no Semana/Dia, resize de duração (só itens com duração), snap 15 min.
- **Backend delta:** `PATCH /crm/follow_ups/:id` aceitando novo `due_at` (reschedule); `expected_close` via `PATCH /crm/cards/:id { expected_close_at }`. WhatsApp agendado: reusar o endpoint de reschedule da PR11 (mensagem agendada).

## B5. Criação rápida
- **MVP:** clicar célula/slot vazio → **quick-add `Popover`** (Título, seletor de tipo, data/hora pré-preenchida, link contato/deal, Salvar + "Mais opções" → form completo). **Botão "+ Novo" sempre visível** (lição Notion Calendar: não esconder criação só em atalho).
- **Full:** drag p/ selecionar faixa de horário; quick-add em linguagem natural PT ("ligar para João amanhã 15h") com chips de confirmação do que foi parseado.

## B6. Detalhe do evento
- **MVP:** clique → `Popover` ancorado com info-chave + **deal & contato clicáveis** (o valor de CRM) + ações por tipo: Lembrete → **Concluir / Adiar (snooze: +1h, amanhã, semana que vem) / Reagendar / Abrir deal**; WhatsApp → **Editar / Reagendar / Cancelar / Enviar agora / Abrir conversa**; Fechamento → **Abrir deal / Mudar data / Ganhar-Perder**.
- **Full:** preview no hover; painel lateral de detalhe.

## B7. Hoje & atrasados
- **MVP:** hoje destacado; lembretes atrasados em **vermelho** + **contador/filtro "N atrasados"** (no CRM, atraso é onde a ferramenta ganha valor). WhatsApp enviado no passado = concluído (dimmed), não "atrasado".
- **Full:** linha "now" viva no Semana/Dia; **roll-forward** de atrasados pro dia de hoje; snooze a partir do atrasado.

## B8. Timezone & localização — **atenção pt_BR**
- Timestamps em UTC, render no fuso do viewer; label do fuso visível no Semana/Dia.
- **Brasil (CLDR) = semana começa no DOMINGO**, não segunda. Default `firstDay = domingo` para pt_BR (configurável). Formato `dd/MM/yyyy`, **24h**, nomes de mês/dia em português (`date-fns/locale/pt-BR`).
- **WhatsApp:** mostrar o fuso explicitamente no evento de envio (evita "enviado às 3h").

## B9. Performance
- **MVP:** buscar só a janela visível (mês ± semana de borda); skeleton da grade no load.
- **Full:** prefetch mês/semana adjacente, cache por range, mutações otimistas com rollback.

## B10. Filtros & overlays
- **MVP:** toggles dos **3 tipos** (☑ Lembretes ☑ WhatsApp ☑ Fechamentos, cada um sua cor) + filtro **meu vs. todos**. Persistir.
- **Full:** overlay por dono, filtro por funil/estágio, legenda em rail lateral, saved filter views.

## B11. Estados
- **MVP:** skeleton da grade; vazio contextual mantendo a grade ("Nada nesta semana — + Agendar follow-up"); erro inline com retry; **drag que falha reverte o evento** + toast.

## B12. Mobile
- **MVP:** abaixo do breakpoint, **Agenda** vira a view primária; detalhe em **bottom sheet**; reagendar via menu de ação (não drag).
- **Full:** faixa de mês compacta com dots (date-picker) acima da agenda; Semana com swipe dia-a-dia.

## B13. BUILD vs. LIBRARY (decisão técnica — tensão com "no custom CSS")
A parte difícil de um calendário **não** são as caixinhas do mês — é o time-grid (empilhamento de sobreposição, hit-testing de drag/resize, snap, linha "now", spanning multi-dia, popover "+N", TZ).

| Opção | Veredito |
|---|---|
| **FullCalendar / Schedule-X** | Completos, mas **trazem CSS próprio** → conflita com o "Tailwind only / no custom CSS" do projeto. **Rejeitado p/ MVP.** |
| **Vue-Cal** | Sem drag real → falha o requisito-core. **Rejeitado.** |
| **Hand-build Mês + Agenda (Vue+Tailwind+date-fns)** | Grade de 7 colunas é só CSS-grid utilitário; baixo risco; **zero conflito de CSS**; reusa libs já no bundle. **Recomendado p/ MVP.** |
| **Time-grid Semana/Dia + drag** | Caro/bugs. **Fase 2** — decidir então entre hand-build vs. abrir exceção pontual de CSS p/ Schedule-X isolado. |

**Recomendação:** envolver tudo num `<CrmCalendar>` próprio onde vivem os 3 tipos, overlays, lógica de atraso e linking deal/contato — a "engine" (hand-build agora; lib depois, se necessário) fica trocável por trás. **MVP = Mês + Agenda hand-build.**

---

## 3. Deltas de backend (consolidado)
1. `Crm::Cards::FilterQuery`: aceitar `sort` + `direction` (campos: `value_cents, next_follow_up_at, last_activity_at, entered_stage_at, title`). *(Lista A3)*
2. Rollup Σ-valor + contagem por grupo (estágio/dono) — endpoint leve ou client. *(A3)*
3. `POST /crm/cards/bulk` — mutação em lote transacional, Pundit-safe, idempotente. *(A4)*
4. `PATCH /crm/follow_ups/:id` — reschedule (`due_at`). *(Calendário B4)*
5. `expected_close` reschedule via `PATCH /crm/cards/:id { expected_close_at }` (já deve aceitar). *(B4)*
6. WhatsApp agendado reschedule/cancel — reusar endpoint da PR11. *(B4/B6)*
7. (Full) tabela `crm_saved_views` p/ Views compartilháveis. *(A0)* — migration additiva, fase final.

Todos additivos. Migrations só na entrega de Saved Views (full). Rodar **gate eager_load** em qualquer `.rb`.

## 4. i18n (en + pt_BR, paridade obrigatória)
Estender `CRM_KANBAN` em `crm.json` (en) e espelho `pt_BR/crm.json`:
- `LIST.*`: `COLUMNS.*` (nomes de coluna), `COLUMN_SETTINGS`, `DENSITY`, `SORT_ASC/DESC`, `GROUP_BY`, `GROUP_TOTAL`, `BULK.{SELECTED,MOVE,ASSIGN,STATUS,DELETE,UNDO}`, `EDIT.{SAVED,ERROR}`, `EMPTY_NO_RESULTS`, `RETRY`.
- `CALENDAR.*`: `VIEW.{MONTH,WEEK,DAY,AGENDA}`, `TODAY`, `MORE` (`+{n} mais`), `OVERDUE_COUNT`, `QUICK_ADD.*`, `EVENT.{COMPLETE,SNOOZE,RESCHEDULE,OPEN_DEAL,EDIT,CANCEL,SEND_NOW,OPEN_CONVERSATION}`, `OVERLAY.{REMINDERS,WHATSAPP,CLOSE_DATES}`, `CONFIRM_MOVE_CLOSE`, `EMPTY_WEEK`.
- Gate de paridade en↔pt_BR (como nas PRs anteriores).

## 5. Faseamento sugerido (PRs próprias)
- **PR-L1 — Lista v2 (base):** TanStack table + colunas (show/hide/reorder/resize/freeze) + sort + paginação + skeleton/empty/erro + responsivo card. *(M–L)*
- **PR-L2 — Lista v2 (poder):** edição inline + bulk actions + group-by com Σ. *(L)*
- **PR-C1 — Calendário v2 (Mês + Agenda):** grade mês hand-build + agenda + navegação + mini-date-picker + overlays de tipo + detalhe popover + estados + pt_BR(domingo). *(L)*
- **PR-C2 — Calendário v2 (interação):** drag-to-reschedule (regras por tipo) + quick-add + atrasados/roll-forward. *(L)*
- **PR-V (full, opcional):** Saved Views compartilháveis (+ migration) e virtualização. *(M)*

Cada PR: orquestração (impl sequenciado + review paralelo + fix-pass) → gates → teste visual real pt_BR → OK do usuário → deploy `connN` com rollback pronto.

## 6. Perguntas abertas (decisão do PO)
1. **Semana/Dia time-grid** entra na v2 (PR-C2) ou fica de fora (Mês+Agenda já cobre o uso)? Se entrar, aceitamos a exceção pontual de CSS de uma lib isolada (Schedule-X) ou hand-build?
2. **Saved Views compartilháveis** (com migration) entram agora ou ficam como "full" futuro? MVP = prefs por usuário em localStorage.
3. **Bulk delete:** soft (archive) ou hard? (recomendo arquivar, reversível.)
4. **Cor do calendário:** confirma "por tipo" como default? (alternativa: por dono.)
5. **Quick-add em linguagem natural PT** é desejado já na v2 ou fica como delight futuro?

## 7. Referências de pesquisa (resumo)
- **Lista:** Linear (multi-seleção/teclado/perf percebida), Attio + Notion + Airtable (Views, edição inline, freeze/densidade, group+subtotais), HubSpot/Pipedrive/Salesforce/Folk (pills, bulk-edit, visibilidade por time), W3C WAI-ARIA Grid (a11y), Carbon/PatternFly (estados).
- **Calendário:** Google Calendar/FullCalendar (conjunto de views, "+N", now-line, DnD), Pipedrive (filtro por tipo, atraso, deep-link ao deal), Notion Calendar/Cron/Motion (quick-add NL, descoberta da criação), CLDR (Brasil = domingo).

## 8. Docs relacionados
[[crm_roadmap_status]] · `docs/crm_kanban_pr10_rollout_rollback.md` (origem do MVP) · `docs/crm_kanban_pr14_plan.md` (filtros/Front 7) · `docs/crm_kanban_connections_plan.md` (webhooks p/ bulk/activities).
