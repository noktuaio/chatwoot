# SLA Inteligente — Rollout & Rollback (conn17)

> Build one-shot das 5 ondas do PRD `docs/crm_sla_v2_prd.md` (manifesto: `docs/crm_sla_v2_build_manifest.md`).
> Imagem: `chatwoot-campaign-import:v4.14.1-20260611-conn17`. Backup pré-build: `backups/crm_sla_v2_prebuild_20260611T083634Z.tgz`.

## O que entra
- **Onda 1 — Motor justo:** `crm_service_schedules` (multi-bloco/dia + fuso IANA, por caixa e por agente), `Sla::BusinessTimeCalculator`, `Sla::ScheduleResolver` (agente atual > caixa > 24/7), `only_during_business_hours` passa a ser respeitado (era no-op).
- **Onda 2 — Grupos:** `Crm::WhatsappGroupDetector` (`@g.us`/`@broadcast`/`@newsletter`, só canais WhatsApp/API), flag `exclude_groups` (default ON) no auto-aplicar, na automação `add_sla` e defensivo no motor.
- **Onda 3 — IA pausa saudável:** `Sla::AiBreachGuard` no momento exato da quebra (schema strict, confiança ≥ 0.6, cache por última mensagem em `applied_slas.metadata`, fail-open). Gate: toggle da política + `CRM_AI_ENABLED` + feature `sla` + credencial.
- **Onda 4 — SLA no CRM + auto-aplicar:** página `crm/sla` (políticas + calendários), Settings → SLA REMOVIDO, auto-aplicar v1 (`conversation_created`, amarra caixas E funis, vazio = todos) via `Crm::SlaAutoApplyJob`; endpoints `crm/service_schedules` (Pundit admin/crm_admin); toggle de horário no criar/editar agente.
- **Onda 5 — Badge:** `SLACardLabel` nos cards do Kanban e na coluna SLA da Lista (payload expõe `applied_sla` + epochs, gated em `feature_enabled?('sla')`).

## Migrations (3, aditivas)
`20260611100000_create_crm_service_schedules`, `20260611100100_add_sla_v2_fields_to_sla_policies` (exclude_groups default true, ai_skip_natural_pause default true, auto_apply jsonb), `20260611100200_add_metadata_to_applied_slas`.
**Obrigatório rodar `db:migrate` no deploy** (schema.rb do fork é stale por padrão).

## Deploy (somente com OK explícito do PO)
```bash
# 1. migrate usando a imagem nova (one-off, mesma rede/env do app)
docker exec $(docker ps -qf name=chat-autonomia_chatwoot_app | head -1) bundle exec rails db:migrate  # ou via service update + entrypoint
# 2. web (start-first) + sidekiq
docker service update --image chatwoot-campaign-import:v4.14.1-20260611-conn17 --no-resolve-image --update-order start-first chat-autonomia_chatwoot_app
docker service update --image chatwoot-campaign-import:v4.14.1-20260611-conn17 --no-resolve-image chat-autonomia_chatwoot_sidekiq
# 3. validação: visual pt_BR (página crm/sla, badge, diálogo de agente) + smoke IA real (AiBreachGuard dry-run conta 6)
```

## Rollback
```bash
docker service update --image chatwoot-campaign-import:v4.14.1-20260610-conn16 --no-resolve-image --update-order start-first chat-autonomia_chatwoot_app
docker service update --image chatwoot-campaign-import:v4.14.1-20260610-conn16 --no-resolve-image chat-autonomia_chatwoot_sidekiq
```
As migrations são aditivas: conn16 ignora as colunas/tabela novas — rollback de imagem NÃO exige rollback de banco.
Cadeia: `conn17 → conn16 → conn15 → conn14 → conn13 → conn12 → conn9 → conn7 → ...`.

## Mudanças de comportamento intencionais no rollout (defaults ON — decisão PO)
1. Políticas EXISTENTES ganham `exclude_groups=true`: conversas de grupo param de acumular quebra imediatamente (reversível por política).
2. Políticas EXISTENTES ganham `ai_skip_natural_pause=true`: a partir do momento em que a conta tem credencial de IA, cada primeira quebra dispara 1 chamada OpenAI (cacheada por mensagem) — custo pequeno e limitado, mas novo.
3. `only_during_business_hours` continua OFF em todas as políticas existentes → cálculo 24/7 idêntico ao atual até alguém ligar o toggle.

## Gates executados (pré-deploy)
- ruby -c (24 .rb) ✅ · eslint 0 erros ✅ · paridade i18n en↔pt_BR (crm.json 774/774, settings.json 587/587) ✅ · vite build ✅
- eager_load + db:chatwoot_prepare + smoke determinístico do cálculo em serviço Swarm temporário (ver progress)
- Review: painel de 7 reviewers (workflow) + fix-pass + GO/NO-GO ✅ · **Codex: SHIP** (1 major N+1 corrigido + 2 minors corrigidos) ✅
- Pendente para a janela do deploy (exige prod): teste visual Playwright em prod + chamada REAL de IA (schema strict) — fazer ANTES de ligar toggles de IA.
