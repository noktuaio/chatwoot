# CRM Kanban PR 13 — IA CRM (GPT-5.4 / Responses API)

## Scope

- Integration card **CRM Kanban IA** (`crm_kanban_ai`) in Settings → Integrações
- OpenAI **Responses API** client (`POST /v1/responses`) for `gpt-5.4` and `gpt-5.4-mini`
- Stage classification: auto-move ≥ **0.80**, suggestion ≥ **0.60**
- Message observer debounce **15s** with job coalescing
- Pipeline AI settings + per-stage `ai_criteria`
- Card drawer: Analisar / Aceitar / Dispensar
- Kanban badge for pending suggestions
- Default **5 stages** including **Perdido**
- Table `crm_ai_stage_suggestions`

## Feature flags

| Flag | Effect |
|------|--------|
| `CRM_KANBAN_ENABLED=false` | Entire CRM off (unchanged) |
| `CRM_AI_ENABLED=false` | Hides integration card, blocks AI APIs, no AI jobs |

## Deploy

1. Set `CRM_AI_ENABLED=true` on web + Sidekiq (alongside `CRM_KANBAN_ENABLED=true`).
2. Build image tag `crm13` from fork.
3. Run migration (`crm_ai_stage_suggestions`).
4. Update web + Sidekiq services.
5. Smoke:
   - Integrations shows **CRM Kanban IA** card
   - Configure API key on account 6
   - Pipeline drawer → IA section saves criteria
   - Card with conversation → evaluate / suggestion flow

## Rollback

1. Revert web + Sidekiq to previous image (`crm12-r1`).
2. Set `CRM_AI_ENABLED=false` (optional, immediate kill-switch).
3. Migration rollback not required for fast rollback; table is additive and harmless when unused.

## Production images (timeline)

| Tag | Notes |
|-----|--------|
| `v4.14.1-20260609-crm13` | PR13 initial deploy |
| `v4.14.1-20260609-crm13-r1` | UX/policy patch: IA section moved above stages, removed confidence % from UI, cooldown 15s, no daily auto-move cap |
| `v4.14.1-20260609-crm13-r2` | **BLOCKER fix**: `CrmAiSettingsPanel`/`CrmCardAiPanel` crashed on mount via `const { showAlert } = useAlert()` (useAlert is a function, not a composable → `TypeError` in `<script setup>`, subtree dropped). Switched to `useAlert(...)` calls; made `isCrmAiEnabled` a real OR fallback (store `=== true` ‖ window `=== 'true'`). New dashboard bundle `dashboard-_zF7MIz5.js`. |
| `v4.14.1-20260609-crm13-r3` | **E2E fix**: AI suggestion failed to persist — `Crm::AiStageSuggestion#reasoning` is `varchar(500)` but the global `ApplicationRecord#validates_column_content_length` caps non-text columns at 255 unless an explicit length validator exists. Added `validates :reasoning, length: { maximum: 500 }`. Backend-only (no migration). |

## Resolution (2026-06-09 — session crm13-r2 / crm13-r3)

**Status: RESOLVED and verified E2E in production.**

- **Root cause of the blocker (not any of the 4 original suspicions):** both `CrmAiSettingsPanel.vue` and `CrmCardAiPanel.vue` did `const { showAlert } = useAlert();`. `useAlert` (`dashboard/composables/index.js`) is a plain function `(message, action) => emitter.emit(...)` returning `undefined`, so the destructure threw `TypeError: Cannot destructure property 'showAlert' of undefined` synchronously in `<script setup>`. The moment the `v-if` gate turned true, Vue aborted mounting the subtree → panel silently absent (matches original suspicion #4, "render error swallowed"). The gate (`isEditing && pipeline?.id && isCrmAiEnabled`) was always correct. Fixed in **crm13-r2** by calling `useAlert(...)` directly and rewriting `isCrmAiEnabled` as a true OR fallback.
- **Integration "Desconectado" was stale:** account 6 `crm_kanban_ai` hook is `enabled` with a saved `api_key` (len 164). Backend `Crm::Ai::Config.enabled?` → `true`.
- **Second bug found via E2E smoke (fixed in crm13-r3):** suggestion persistence raised `Reasoning is too long (maximum is 255 characters)`. Cause: global `ApplicationRecord#validates_column_content_length` caps any `string` column at 255 unless an explicit `:length` validator exists; `reasoning` is `varchar(500)` and gpt-5.4 returns up to ~500 chars. Added `validates :reasoning, length: { maximum: 500 }` to `Crm::AiStageSuggestion`. No migration (column already 500).
- **E2E verification (prod):** `Crm::Ai::Evaluator` on card #42 → gpt-5.4, confidence 0.94 → suggestion persisted (id 1, reasoning 305 chars) → **auto-moved** "Novo" → "Em atendimento" (status `auto_applied`). Live asset `dashboard-_zF7MIz5.js` served (old `dashboard-DJT_Jfeh.js` → 404), no buggy destructure in the served bundle.

### Rollback for crm13-r2 / crm13-r3

Revert web + Sidekiq to `chatwoot-campaign-import:v4.14.1-20260609-crm13-r1` (`docker service update --image ... --no-resolve-image`). No DB change to undo. Pre-deploy service inspects: `backups/crm_kanban_pr13_r2_prebuild_20260609T075846Z/predeploy/`.

---

## Known open issues (RESOLVED — kept for history)

### BLOCKER — Seção **IA do funil** não aparece em **Editar funil**

**Reported:** account 6, pipeline **Seguro Viagem** (id=9), after `crm13` and `crm13-r1` deploy.

**Expected:** In `CrmPipelineDrawer`, section `CrmAiSettingsPanel` with title **IA do funil** immediately below Nome/Descrição, before Etapas.

**Observed in UI:** Drawer shows Nome → Descrição → Etapas → Inbox e automação. No IA block.

**Verified on server (does NOT explain missing UI):**

- `CRM_AI_ENABLED=true` on web + Sidekiq
- `window.globalConfig.CRM_AI_ENABLED` is `"true"` on `/app/accounts/6/crm`
- Active bundle: `dashboard-DJT_Jfeh.js` (contains `CrmAiSettingsPanel`, `crmAiEnabled`)
- Backend: pipeline id=9 has `metadata.ai.auto_move_enabled=true` and stage `ai_criteria` backfilled

**Suspected causes to investigate next session:**

1. Frontend `v-if` gate in `CrmPipelineDrawer.vue` (`isEditing && pipeline?.id && isCrmAiEnabled`) — confirm `pipeline` prop binding in template when using `const props = defineProps(...)`; try `props.pipeline?.id` explicitly.
2. Vuex `globalConfig/get.crmAiEnabled` vs `window.globalConfig.CRM_AI_ENABLED` mismatch at runtime (store may be `false` while window is `"true"`).
3. Browser/CDN cache serving an older dashboard chunk (user should hard-refresh; if still broken, issue is code-side).
4. Component render error swallowed (check browser console on drawer open).

**Files:**

- `app/javascript/dashboard/routes/dashboard/crm/components/CrmPipelineDrawer.vue` (lines ~39–44, ~303–307)
- `app/javascript/shared/store/globalConfig.js`
- `app/controllers/dashboard_controller.rb` (`CRM_AI_ENABLED` in `app_config`)

**Suggested fix direction:** Remove or simplify frontend kill-switch for pipeline drawer (backend already returns `crm.ai.disabled`); always render `CrmAiSettingsPanel` in edit mode when `pipeline.id` exists; add Vitest/E2E assertion that section mounts.

---

### OPEN — Integração **CRM Kanban IA** mostra **Desconectado**

**URL:** `/app/accounts/6/settings/integrations/crm_kanban_ai`

**Impact:** Evaluations return `credentials_missing` until OpenAI API key is saved and hook enabled.

**Not the same as missing pipeline IA section** (integration status should not gate `CrmAiSettingsPanel`), but blocks end-to-end AI test.

---

### RESOLVED in `crm13-r1` — UI não deve expor limiares internos

- Removed user-facing text mentioning confidence ≥ 80% / 60%
- Removed `auto_move_threshold` / `suggestion_threshold` from `GET ai_settings` payload
- Card suggestion shows stage name only (no `% confiança`)

---

### RESOLVED in `crm13-r1` — Limites de auto-move

| Rule | Before | After (`crm13-r1`) |
|------|--------|---------------------|
| Cooldown between auto-moves (same card) | 30 min | **15 s** (`AUTO_MOVE_COOLDOWN_SECONDS = DEBOUNCE_SECONDS`) |
| Max auto-moves per card per day | 3 | **removed** (`MAX_AUTO_MOVES_PER_DAY` deleted) |

Internal thresholds unchanged: auto-move ≥ 0.80, suggestion ≥ 0.60 (backend only).

---

## Next session checklist

1. Reproduce missing **IA do funil** with browser devtools: `window.globalConfig`, Vuex `globalConfig/get`, and DOM query for `CrmAiSettingsPanel`.
2. Apply fix (likely remove `isCrmAiEnabled` v-if or fix prop binding).
3. Rebuild Vite → image `crm13-r2` → deploy web + Sidekiq.
4. Confirm IA section visible in **Editar funil** on account 6.
5. Connect **CRM Kanban IA** integration (API key).
6. Smoke: pipeline IA save, card **Analisar agora**, auto-move on new messages.
