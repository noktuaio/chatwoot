# Épico — Tuning de modelo/effort + Prompt Caching + Telemetria de IA (CRM / Autonom.ia)

Status: PLANEJADO (não implementado). Decidido com Rodrigo em 2026-06-28.

Objetivo: ajustar modelo/`reasoning_effort` por feature conforme risco, reduzir
custo com prompt caching da OpenAI, e fechar a lacuna de telemetria de uso/custo.

Todas as IAs do projeto rodam OpenAI (Responses API via `Crm::Ai::ResponsesClient`
e RubyLLM no Captain core). Anthropic/Gemini/Bedrock só aparecem como catálogo
"coming soon" — sem client real.

---

## Fase 1 — Tuning de modelo + reasoning_effort

Cada linha: estado atual → alvo, e onde mexer. `low/medium/high/xhigh` são os
efforts suportados (validados por probe no endpoint).

| # | Feature | Mudança | Local |
|---|---------|---------|-------|
| 1 | Avaliação do card (classify + auto-move) | modelo auto-move `gpt-5.4` → **`gpt-5.4-mini`**; effort **único `xhigh`** (classify E auto-move) | `config.rb:15` (MODEL_AUTO_MOVE) + `CLASSIFY_REASONING_EFFORT 'high'→'xhigh'` (`config.rb:24`, já usado p/ ambos no `evaluator.rb:55`). **Sem separar** — um effort só, por decisão do PO. |
| 2 | Rascunho convite reunião | effort `low` → **`high`** | `draft_invite_service.rb:14` (REASONING_EFFORT) |
| 3 | Resumo de reunião | effort `high` → **`xhigh`** | `meeting_summary_service.rb:22` — usar valor dedicado `'xhigh'` (NÃO o `SUMMARY_REASONING_EFFORT`, p/ não afetar o resumo de card) |
| 4 | SLA breach guard (EE) | effort `low` → **`high`** | `enterprise/app/services/sla/ai_breach_guard.rb:75` |
| 5 | Agent Builder (coletar) | effort `low` → **`medium`** | `autonomia/agents/config.rb:14` (BUILDER_REASONING_EFFORT_COLLECT) |
| 6 | Answerer / Operate / Testar / Guia | effort `low` → **`medium`** | `autonomia/agents/config.rb:68` (ANSWERER_REASONING_EFFORT) |
| 7 | Copilot conversa (genérico) | modelo `gpt-5.4-mini` → **`gpt-5.4`**; effort `low` → **`medium`** | `autonomia/copilot/conversation_copilot.rb:75` (model + reasoning_effort hardcoded) |
| 8 | KB Reviewer | effort `low` → **`medium`** | `autonomia/agents/config.rb:28` (REVIEWER_REASONING_EFFORT) |
| 9 | KB Instruction refresh | **já é `medium`** — sem mudança | `autonomia/agents/config.rb:34` (= BUILDER_REASONING_EFFORT_FINAL) ✅ |
| 10 | Email campaign builder/rewrite | modelo `gpt-5.4`/`gpt-5.4-mini` confirmado; effort **não setado → `medium`** | adicionar `reasoning_effort: 'medium'` no fluxo `email_campaigns/ai` (submit job / chamada Responses) |

Risco/observações:
- (#1) Auto-move age SEM humano. Baixar para `mini` reduz custo mas `mini` é mais
  fraco; subir effort p/ `xhigh` compensa parte. Monitorar taxa de auto-move
  errado via `crm_ai_stage_suggestions` (confidence) + atividades `ai_auto_moved`.
- Net de custo da Fase 1: vários efforts sobem + copilot vai a `gpt-5.4` → tende a
  AUMENTAR custo. Por isso a Fase 2 (caching) entra junto p/ compensar.
- Mudanças são de config; sem regressão de comportamento além do esperado.

Aceite Fase 1: efforts/modelos batem a tabela (avaliação do card = um effort
`xhigh`); lint + Codex review; smoke de auto-move/copilot/email.

---

## Fase 2 — Prompt caching OpenAI (reduzir custo)

Findings (docs OpenAI, jun/2026):
- Caching é AUTOMÁTICO em gpt-4o+ (sem código). Ativa com prompt **≥1024 tokens**.
  Economia **até 90%** no input cacheado; latência **até −80%**.
- gpt-5.4 suporta **cache estendido 24h** (não só os 5–10 min in-memory).
- Hit depende de **prefixo idêntico**: estático no INÍCIO, dinâmico no FIM.
- `prompt_cache_key` melhora roteamento/hit-rate (manter < ~15 req/min por chave).
- Medir via `usage.prompt_tokens_details.cached_tokens`.

A nosso favor: `ResponsesClient.base_body(model, instructions, input, schema, ...)`
já separa `instructions` (estático/sistema) de `input` (dinâmico). Logo o prefixo
estático já tende a existir.

Plano:
1. **Garantir prefixo estável ≥1024 tokens** por feature: mover TODO conteúdo fixo
   (regras, exemplos, schema, definição de etapas do funil quando estável) para o
   início de `instructions`; deixar só o variável (conversa/card/contato) no `input`.
   Revisar prompts que hoje interpolam dados no meio das instruções.
2. **Adicionar `prompt_cache_key`** no `base_body` do `ResponsesClient`, derivado de
   feature + (quando fizer sentido) pipeline/account — ex.: `crm:classify:<account>`,
   `email:build:<account>`. Estabiliza roteamento.
3. **Aproveitar cache 24h do gpt-5.4** para features de prefixo grande e recorrente
   (auto-move/classify, email builder, answerer): nada a fazer além de (1)+(2),
   mas validar via `cached_tokens`.
4. **Não** quebrar features de prompt curto (<1024 tok) — caching simplesmente não
   ativa; sem custo extra.

Aceite Fase 2: `cached_tokens` > 0 e crescente nas features de alto volume;
relatório antes/depois de custo médio por chamada.

---

## Fase 3 — Telemetria de uso/custo (fecha a lacuna)

Hoje NÃO há acompanhamento centralizado de custo/consumo de IA:
- Captain conta nº de respostas/documentos (quota em Billing) — não tokens/custo.
- Langfuse/OpenTelemetry é OPCIONAL (`OTEL_PROVIDER=langfuse`), desligado por padrão.
- `ResponsesClient` só loga modelo/latência ad-hoc, sem agregação.
- Nenhuma feature Nossa (CRM/Autonom.ia) registra tokens nem custo.

### 3.1 Captura de uso (backend)
1. Tabela `crm_ai_usage_events`: `feature`, `account_id`, `model`, `input_tokens`,
   `cached_tokens`, `output_tokens`, `reasoning_effort`, `cost_estimate`,
   `latency_ms`, `created_at`. **NUNCA** gravar prompt/instruções/resposta — só
   metadados de consumo.
2. Popular no `ResponsesClient` a partir do `usage` da resposta (já temos `usage`
   em memória em vários pontos — hoje descartado).
3. Custo estimado por tabela de preço por modelo (config), distinguindo input
   cacheado (desconto) de não-cacheado.

> REGRA (PO): a página Gestão IA só começa a ser codada APÓS mockups reais
> aprovados pelo Rodrigo. Construção usando a skill **frontend-design** (regra
> máxima de qualidade visual).

### 3.2 Página "Gestão IA" (CRM → sub-página)
Nova sub-página dentro do CRM (ao lado de Kanban/Calendário/Dashboard/SLA):
nav em `crm.routes.js` + item no menu CRM. Dashboard de gasto **em tempo real**,
**simples para o usuário entender** (não técnico):

- **Cards de topo:** gasto hoje / semana / mês (R$), nº de chamadas, % cache (economia).
- **Por onde:** gasto por feature (auto-move, resumo, follow-up, copilot, email…)
  em linguagem de produto, não nome de classe.
- **Quando:** série temporal (dia/hora) do gasto.
- **Tempo real:** atualização via poll leve ou ActionCable (reusar padrão do board).
- **Exportar analítico (logs):** CSV/JSON dos eventos de uso — colunas: data/hora,
  feature, conta, modelo*, tokens (in/cache/out), custo. *(ver privacidade)*

### 3.3 Privacidade + RBAC (crítico)
- **NUNCA expor** instruções (prompts) nem respostas da IA — nem na tela nem no
  export. Só consumo: o quê (feature), quando, onde (conta/funil), quanto (tokens/R$).
- **Modelo utilizado**: visível **apenas para super-admin**. Para admin de conta:
  mostra gasto/feature/tempo, **sem** o nome técnico do modelo.
- Export herda a mesma regra: coluna "modelo" só sai no export do super-admin.
- Escopo de dados: admin de conta vê só a própria conta; super-admin vê todas.

### 3.4 (Opcional) Langfuse
Ligar Langfuse em prod p/ tracing detalhado interno (não exposto ao cliente),
complementando a tabela.

Aceite Fase 3: toda chamada Responses grava 1 evento de uso (sem conteúdo);
página Gestão IA mostra gasto em tempo real + % cache; export CSV/JSON respeitando
RBAC; modelo só p/ super-admin; nenhum prompt/resposta vaza em tela ou export.

---

## Sequência sugerida
Recomendado: **Fase 3 → Fase 1 → Fase 2** — mede baseline de custo ANTES das
mudanças de effort, depois ajusta, depois otimiza com caching validado pelos dados.
