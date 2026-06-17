# CRM Kanban Pro PR 12 Rollout And Rollback

## Scope

PR 12 adds stage automations with enter/exit triggers, multiple rules per stage, and delayed action sequences.

Included:

- `crm_stage_automations`, `crm_stage_automation_steps`, `crm_stage_automation_executions`
- triggers: `on_enter`, `on_exit`
- actions: `create_follow_up`, `assign_owner`, `move_stage`
- delayed steps via `Crm::StageAutomationStepJob`
- idempotent executions keyed by `card_id + stage_automation_id + trigger_token`
- automation depth guard (`MAX_AUTOMATION_DEPTH = 3`)
- admin API under `/crm/stages/:stage_id/stage_automations`
- pipeline drawer UI per stage (`CrmStageAutomationsPanel`)

Not included in PR 12:

- AI auto-move
- n8n webhooks / tokens
- supervisor / reports
- billing / licensing / marketplace logic

## Feature Flag

PR 12 remains behind:

```bash
CRM_KANBAN_ENABLED=true|false
```

When disabled:

- CRM routes are blocked by the existing CRM base controller guard.
- CRM sidebar/routes are hidden by frontend global config.
- `Crm::StageAutomationStepJob` returns without processing.

## Required Deploy Order

1. Build the custom image from the current fork (`crm12` tag).
2. Create a pre-deploy backup:
   - web and Sidekiq service inspect files;
   - current task snapshots;
   - current rollback image inspect;
   - candidate image inspect;
   - current `progress.md`;
   - PostgreSQL dump.
3. Run database migration:
   - `bundle exec rails db:migrate`
4. Update Swarm services (web + Sidekiq) to the new image.
5. Smoke test:
   - open pipeline drawer, configure an `on_enter` rule with `create_follow_up`;
   - move a card into the stage and confirm follow-up creation;
   - move card out with `on_exit` + `assign_owner` and confirm owner change;
   - confirm disabled rules do not run.

## Rollback Image

Rollback PR 12 only:

```text
chatwoot-campaign-import:v4.14.1-20260608-crm11-r2
```

Rollback PR 11 hotfix as well:

```text
chatwoot-campaign-import:v4.14.1-20260608-crm10
```

## Rollback Steps

1. Revert web and Sidekiq to `crm11-r2`.
2. Do not drop PR 12 tables in production rollback.
3. PR 12 migrations are additive; old image ignores new tables safely.
4. Disable automations in UI or set `enabled=false` if partial rollback is needed before image revert.

## Data Safety

- Migrations are additive only.
- Undo for automations is operational: disable or delete rules in the pipeline drawer.
- Executions are audit/history records; no destructive rollback job in V1.
- `move_stage` automations respect depth limit to avoid infinite loops.

## Verification Checklist

- [x] Production migration `CRM12_PRODUCTION_MIGRATION_OK` (2026-06-08).
- [x] Web + Sidekiq converged on `chatwoot-campaign-import:v4.14.1-20260608-crm12`.
- [x] HTTP smoke `/api`, `/app/login`, `/app/accounts/6/crm` returned 200.
- [x] Transactional smoke with rollback on account 6: `on_enter` + `create_follow_up` worked and left no persistent data.
- [ ] Admin UI validation in pipeline drawer (manual).
- [ ] Sequence steps run in order; delayed non-follow-up steps enqueue Sidekiq jobs (manual).
- [ ] Agents cannot access stage automation APIs (covered by request specs).
- [ ] `CRM_KANBAN_ENABLED=false` blocks API and jobs (covered by request specs).

## Production Deploy Record (2026-06-08)

- Pre-deploy backup: `/root/docker-stacks/backups/crm_kanban_pr12_predeploy_20260608T213329Z`
- Migration service: `crm12_migrate_213344`
- Candidate image: `chatwoot-campaign-import:v4.14.1-20260608-crm12`
- Rollback image: `chatwoot-campaign-import:v4.14.1-20260608-crm11-r2`
