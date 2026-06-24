# Retorno por data ("me liga terça que vem") → lembrete automático

**Status:** Fase 1 implementada (autonomia25), testada com LLM real, aguardando OK de deploy.

## Ideia
O pipeline de IA do CRM já lê TODA mensagem (StageClassifier). Quando o cliente pede um retorno com
data concreta ("me liga terça que vem de tarde", "retorna dia 15 às 10h"), a IA resolve a data e
criamos um LEMBRETE (`Crm::FollowUp` reminder_only, type=call) — que já aparece no calendário e no
popup de lembrete sem código extra.

## Reúso × novo
- ♻️ Pipeline `ConversationObserverListener → CardSyncer → Ai::Observer (debounce 15s) → EvaluateCardJob → Evaluator → StageClassifier`.
- ♻️ `Crm::FollowUp` (reminder_only, due_at, type call) + `FollowUpDueJob` (1min) + `DueProcessor` (vira overdue no vencimento) + calendário (`calendar_controller#follow_up_events` por due_at) + popup (`ReminderPopupQuery`).
- 🆕 Extração da data + criação do lembrete.

## Mudanças (Fase 1)
1. `crm/ai/stage_classifier.rb` — campo `callback_request {detected, requested_at, requested_at_text, confidence}` no schema (piggyback, sem chamada nova) + instruções de resolução de data (regras de hora manhã/tarde/noite + default) usando AGORA+fuso.
2. `crm/ai/context_builder.rb` — injeta `temporal {timezone, now_local, weekday, default_hour}` para ancorar datas relativas.
3. `crm/ai/evaluator.rb` — `run_callback` best-effort após a classificação.
4. 🆕 `crm/follow_ups/callback_scheduler.rb` — parse no fuso → due_at UTC; guardas (detected, confiança ≥0.6, data concreta/futura, ≤180d); dedup/upsert (1 lembrete IA pendente por card, data mais recente vence); cria `reminder_only`/`call`.
5. `crm/ai/config.rb` — `CALLBACK_MIN_CONFIDENCE=0.6`, `CALLBACK_MAX_HORIZON_DAYS=180`, `CALLBACK_DEFAULT_HOUR=9`, `callback_detection_enabled?` (ENV `AI_CALLBACK_DETECTION`), `resolved_timezone`.

## Gates / segurança
- ENV `AI_CALLBACK_DETECTION` (default ON) + herda o gate de IA do CRM (só contas com chave).
- Reminder-only (dano mínimo, humano confirma/liga). Sem migração. Calendário/popup intactos.

## Testado (LLM real, conta 12) — 10/10
Scheduler: cria/dedup/upsert, não cria em vago/conf baixa/passado/horizonte/kill-switch, event_type correto.
LLM: "terça que vem de tarde" (hoje qua 17/06) → `2026-06-23T14:00`; "me liga depois" → não detecta.

## Fase 2 (futuro, opcional)
Mensagem auto-agendada (reusa `MessageSender` + janela WhatsApp 24h) opt-in por pipeline; auto-confirmação com o cliente.
