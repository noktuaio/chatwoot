# Prunes idempotency records past their 24h TTL (plan §3.3). Keeps the
# idempotency_keys table bounded; expired keys free up for reuse and stale
# :processing rows (left by a crashed/failed request) stop blocking retries.
class Crm::IdempotencyKeysCleanupJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    IdempotencyKey.where(created_at: ..IdempotencyKey::TTL.ago).in_batches.delete_all
  end
end
