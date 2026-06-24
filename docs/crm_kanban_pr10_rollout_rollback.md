# CRM Kanban Pro PR 10 Rollout And Rollback

## Scope

PR 10 adds CRM follow-ups, CRM List MVP, and CRM Calendar MVP.

Included:

- `crm_follow_ups`
- `crm_cards.next_follow_up_at`
- follow-up CRUD API
- follow-up complete/cancel actions
- reminder-only follow-ups
- snooze/reopen follow-ups for linked conversations
- due follow-up processor scheduled by Sidekiq cron
- CRM List MVP
- CRM Calendar MVP
- drawer Follow-ups tab

Not included in PR 10:

- automatic message sending
- WhatsApp provider dispatch from CRM
- AI auto-move
- stage automations
- n8n webhooks/tokens
- offers, checklists, custom CRM fields
- supervisor/reports
- billing, licensing, marketplace, or commercial token logic

## Feature Flag

PR 10 remains behind:

```bash
CRM_KANBAN_ENABLED=true|false
```

When disabled:

- CRM routes are blocked by the existing CRM base controller guard.
- CRM sidebar/routes are hidden by frontend global config.
- `Crm::FollowUpDueJob` returns without processing.

## Required Deploy Order

1. Build the custom image from the current fork.
2. Create a pre-deploy backup:
   - web and Sidekiq service inspect files;
   - current task snapshots;
   - current rollback image inspect;
   - candidate image inspect;
   - current `progress.md`;
   - validated PostgreSQL custom-format dump.
3. Run migrations with the candidate image before switching long-running services.
4. Update Rails web service to the candidate image.
5. Run web runtime smoke.
6. Update Sidekiq service to the same candidate image.
7. Run Sidekiq runtime smoke.
8. Run CRM PR 10 smoke tests.
9. Watch recent web/Sidekiq logs.

## Smoke Tests

Required before considering PR 10 deployed:

- `/api` returns HTTP 200.
- `/app/login` returns HTTP 200.
- CRM route returns HTTP 200 when the app is up.
- Rails can load:
  - `Crm::FollowUp`
  - `Crm::FollowUpDueJob`
  - `Crm::FollowUps::DueProcessor`
  - `Crm::Cards::CalendarQuery`
- Sidekiq can load `Crm::FollowUpDueJob`.
- With `CRM_KANBAN_ENABLED=false`, follow-up endpoints return the CRM disabled response and the due job does not process.
- With `CRM_KANBAN_ENABLED=true`, a rollback-protected smoke can:
  - create a standalone card;
  - create a reminder follow-up;
  - create a snooze follow-up for a linked conversation;
  - complete a follow-up idempotently;
  - query calendar events;
  - process an overdue follow-up;
  - confirm no persistent test rows remain after forced rollback.

## Fast Rollback

If anything looks wrong after deploy:

1. Set `CRM_KANBAN_ENABLED=false` on web and Sidekiq.
2. Restart web and Sidekiq.
3. Confirm CRM endpoints are blocked by the disabled flag.

The new table and columns are additive and can safely remain in place while disabled.

## Image Rollback

If the candidate image must be rolled back:

1. Set `CRM_KANBAN_ENABLED=false`.
2. Roll web back to the previous known-good image.
3. Roll Sidekiq back to the previous known-good image.
4. Confirm both services converge to `1/1`.
5. Run `/api`, `/app/login`, and recent log smoke checks.

## Database Rollback

Do not drop CRM PR 10 data in normal rollback.

The safe rollback is to leave:

- `crm_follow_ups`
- `crm_cards.next_follow_up_at`
- PR 10 indexes

If destructive database rollback is explicitly approved and a fresh backup exists, drop only PR 10 additions in reverse dependency order:

```sql
DROP TABLE IF EXISTS crm_follow_ups;
ALTER TABLE crm_cards DROP COLUMN IF EXISTS next_follow_up_at;
```

This destructive path must not be used if any real CRM follow-up data should be preserved.

## Compatibility Notes

- Base Campanha remains controlled by `CAMPAIGN_IMPORT_ENABLED`.
- WhatsApp API campaigns remain controlled by `WHATSAPP_API_CAMPAIGNS_ENABLED`.
- PR 10 does not delete contacts, conversations, labels, campaign imports, WhatsApp API campaigns, or CRM cards.
- PR 10 does not modify the functional behavior of Base Campanha or WhatsApp API campaigns.
