# CRM Kanban Pro PR 11 Rollout And Rollback

## Scope

PR 11 adds scheduled auto-send follow-ups for WhatsApp-capable linked conversations.

Included:

- `automation_mode: auto_send_message` enabled for CRM follow-ups
- free-form message send inside the WhatsApp 24-hour window
- official template fallback outside the 24-hour window
- API inbox fallback via `whatsapp_api_message_template_id`
- native WhatsApp fallback via `template_name` + `template_language`
- `Crm::FollowUps::MessageSender`
- `Crm::FollowUps::MessagingWindow`
- due processor auto-send path with idempotent `sent_message_id`
- drawer UI for message body and template fallback
- `GET /crm/follow_ups/messaging_window`

Not included in PR 11:

- stage automations / sequences
- AI auto-move
- n8n webhooks / tokens
- supervisor / reports
- billing / licensing / marketplace logic

## Feature Flag

PR 11 remains behind:

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
3. Update Rails web service to the candidate image.
4. Update Sidekiq service to the same candidate image.
5. Run CRM PR 11 smoke tests.
6. Watch recent web/Sidekiq logs.

PR 11 adds no new migrations.

## Smoke Tests

Required before considering PR 11 deployed:

- `/api` returns HTTP 200.
- `/app/login` returns HTTP 200.
- CRM route returns HTTP 200 when the app is up.
- Rails can load:
  - `Crm::FollowUps::MessageSender`
  - `Crm::FollowUps::MessagingWindow`
- Sidekiq can load `Crm::FollowUpDueJob`.
- With `CRM_KANBAN_ENABLED=false`, follow-up auto-send endpoints return the CRM disabled response and the due job does not process.
- With `CRM_KANBAN_ENABLED=true`, a rollback-protected smoke can:
  - create an auto-send follow-up with `message_body` only when the linked conversation is inside the 24-hour window;
  - create an auto-send follow-up with `message_body` and template fallback when outside the window;
  - query `messaging_window` for a linked WhatsApp conversation;
  - process a due auto-send follow-up inside a forced rollback transaction;
  - confirm no persistent test rows remain after forced rollback.

## Fast Rollback

If anything looks wrong after deploy:

1. Set `CRM_KANBAN_ENABLED=false` on web and Sidekiq.
2. Restart web and Sidekiq.
3. Confirm CRM endpoints are blocked by the disabled flag.

No PR 11 database rollback is required.

## Production Image History

- Initial PR 11 deploy: `chatwoot-campaign-import:v4.14.1-20260608-crm11`
- Hotfix deploy (24h window validation): `chatwoot-campaign-import:v4.14.1-20260608-crm11-r2`

The hotfix makes template fallback required only when `MessagingWindow#requires_template?` is true at follow-up creation time.

## Image Rollback

If the candidate image must be rolled back:

1. Set `CRM_KANBAN_ENABLED=false`.
2. Roll web back to `chatwoot-campaign-import:v4.14.1-20260608-crm10` (or `crm11` if only reverting the hotfix).
3. Roll Sidekiq back to the same rollback image.
4. Confirm both services converge to `1/1`.
5. Run `/api`, `/app/login`, and recent log smoke checks.

## Database Rollback

PR 11 is code-only. No destructive database rollback is required.

Existing `crm_follow_ups.metadata` rows created during evaluation can remain in place while disabled.

## Compatibility Notes

- Base Campanha remains controlled by `CAMPAIGN_IMPORT_ENABLED`.
- WhatsApp API campaigns remain controlled by `WHATSAPP_API_CAMPAIGNS_ENABLED`.
- PR 11 does not delete contacts, conversations, labels, campaign imports, WhatsApp API campaigns, or CRM cards.
- PR 11 does not modify the functional behavior of Base Campanha or WhatsApp API campaigns.
