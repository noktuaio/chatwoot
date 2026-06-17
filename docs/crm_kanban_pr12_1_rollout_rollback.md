# CRM Kanban PR 12.1 — Global Follow-up Reminder Popup

## Scope

PR 12.1 adds a global in-app popup when reminder follow-ups become due.

Included:

- popup for `automation_mode: reminder_only` and `snooze_conversation`
- ActionCable event `crm.follow_up.due`
- global modal in `Dashboard.vue` (any route)
- buttons **Concluir** (`complete`) and **Dispensar** (`dismiss_reminder`)
- one popup per follow-up per user until completed/canceled/dismissed
- bootstrap poll `GET /crm/follow_ups/reminders` on dashboard load (missed events)

Not included:

- browser push with tab closed
- popup for `auto_send_message` (PR11 path)

## APIs

- `GET /api/v1/accounts/:account_id/crm/follow_ups/reminders`
- `POST /api/v1/accounts/:account_id/crm/follow_ups/:id/dismiss_reminder`

## Feature flag

Still behind `CRM_KANBAN_ENABLED=true|false`.

## Deploy

1. Build image tag `crm12-r1` (or next patch) from fork with PR12.1 changes.
2. No new migrations required.
3. Update web + Sidekiq.
4. Smoke: create overdue `reminder_only` follow-up, confirm popup on inbox route, dismiss once, confirm it does not reappear.

### Deploy record (2026-06-08)

- Image: `chatwoot-campaign-import:v4.14.1-20260608-crm12-r1`
- Backup: `/root/docker-stacks/backups/crm_kanban_pr12_1_predeploy_20260608T220245Z`
- Services updated: `chat-autonomia_chatwoot_app`, `chat-autonomia_chatwoot_sidekiq`
- Also includes PR12 UI fix: stage automation delay/action fields no longer overlap in pipeline drawer.

## Rollback

Revert web + Sidekiq to previous image (`crm12` or `crm11-r2`). Dismiss metadata in `crm_follow_ups.metadata` is harmless.
