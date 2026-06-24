# CRM Kanban Pro PR 1 Rollout And Rollback

## Scope

This document covers the CRM Kanban Pro PR 1 backend base only.

PR 1 adds only additive CRM tables and backend API endpoints under:

`/api/v1/accounts/:account_id/crm`

PR 1 does not include CRM frontend UI, AI automation, follow-ups, scheduled messages, billing, licensing, or marketplace logic.

## Feature Flag

Keep the CRM API disabled until migrations and smoke tests pass:

```bash
CRM_KANBAN_ENABLED=false
```

When disabled, CRM API endpoints return `404` with:

```json
{ "error": "crm.disabled" }
```

## Required Deploy Order

1. Build the custom image from the current Chatwoot fork.
2. Keep `CRM_KANBAN_ENABLED=false` on web and Sidekiq.
3. Run database migrations using the new image before switching long-running services.
4. Update the Rails web service to the new image.
5. Update the Sidekiq service to the same new image.
6. Confirm both services are healthy.
7. Run smoke tests with the flag disabled.
8. Enable `CRM_KANBAN_ENABLED=true` only when the user explicitly authorizes evaluation.

This order matters because core models include additive associations to the new `crm_*` tables. Running new web/Sidekiq code before migrations can make code paths that touch those associations fail against missing tables.

## Smoke Tests

With `CRM_KANBAN_ENABLED=false`:

- `GET /api/v1/accounts/:account_id/crm/cards` returns `404`.
- Existing Base Campanha import endpoints still work according to their own flag.
- Existing WhatsApp API campaign endpoints still work according to their own flag.
- `/api` health returns queue and data services as OK.

After enabling `CRM_KANBAN_ENABLED=true` for evaluation:

- Admin can create a standalone CRM card.
- Admin can move a card through `POST /crm/cards/:id/move`.
- Generic `PATCH /crm/cards/:id` cannot change stage or pipeline.
- Agent without inbox access cannot read an inbox card by direct URL.
- In `assigned_only` mode, an agent cannot create/link/unlink cards using conversations assigned to another agent.
- Kanban returns paginated cards per stage with `has_more` and `next_cursor`.

## Fast Rollback

If anything looks wrong after deploy:

1. Set `CRM_KANBAN_ENABLED=false` on web and Sidekiq.
2. Restart web and Sidekiq.
3. Confirm CRM endpoints return `404`.

The CRM tables can remain in the database. They are additive and are not used when the flag is disabled.

## Code Rollback

If the new image must be rolled back:

1. Set `CRM_KANBAN_ENABLED=false`.
2. Roll web and Sidekiq back to the previous known-good image.
3. Leave the `crm_*` tables in place.

Leaving additive tables in place is the safest rollback path and preserves any evaluation data.

## Destructive Database Rollback

Do not drop CRM tables after users have created CRM data unless the user explicitly approves data loss or the data has been exported.

If destructive rollback is explicitly approved before any real CRM data is created, drop tables in reverse dependency order:

```sql
DROP TABLE IF EXISTS crm_activities;
DROP TABLE IF EXISTS crm_card_conversations;
DROP TABLE IF EXISTS crm_cards;
DROP TABLE IF EXISTS crm_inbox_settings;
DROP TABLE IF EXISTS crm_pipeline_inboxes;
DROP TABLE IF EXISTS crm_pipeline_stages;
DROP TABLE IF EXISTS crm_pipelines;
```

Before destructive rollback, create a PostgreSQL backup and keep the application image rollback target available.

## Compatibility Notes

- Base Campanha remains controlled by `CAMPAIGN_IMPORT_ENABLED`.
- WhatsApp API campaigns remain controlled by `WHATSAPP_API_CAMPAIGNS_ENABLED`.
- CRM PR 1 adds no Sidekiq jobs.
- CRM PR 1 does not delete contacts, conversations, labels, messages, campaign imports, or WhatsApp API campaign data.
