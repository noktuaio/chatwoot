# Campaign Import Rollback

## Disable The Feature

Set the feature flag to false and restart the Rails and Sidekiq processes:

```sh
CAMPAIGN_IMPORT_ENABLED=false
```

When disabled, the UI entry point is hidden, API endpoints return blocked responses, and campaign import jobs return without work.

## Roll Back Application Code

Deploy the previous custom image or restore the pre-change application backup created before this implementation.

The pre-change backup for this workspace is:

```text
/root/docker-stacks/backups/chatwoot_public_pre_campaign_import_20260603211141.tar.gz
```

## Database Rollback Notes

The migrations are additive. They create only:

- `campaign_imports`
- `campaign_import_rows`
- `campaign_import_labels`

No existing Chatwoot tables are destructively modified.

## Data Safety

V1 never deletes contacts.

The undo action only removes labels recorded in `campaign_import_rows.labels_applied` for that specific campaign import. It does not remove unrelated labels and does not delete contacts.

Labels created by the feature use `show_on_sidebar=false`, so disabling the feature does not expose campaign labels in the sidebar.

`campaign_import_rows` stores masked phone values and SHA-256 hashes, not full phone numbers. The generated normalized CSV is a protected import artifact and keeps normalized full phones for up to 30 days so a validated import can be confirmed later. Error CSV downloads use masked phone values.
