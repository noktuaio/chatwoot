module Webhooks
  # Dedicated delivery job for CRM outbound webhooks (plan D5/B1).
  #
  # WHY A SEPARATE JOB: the core account-webhook path is at-most-once — for the
  # :account_webhook type, Webhooks::Trigger#execute calls handle_failure which
  # SWALLOWS timeouts/5xx (no re-raise), and ApplicationJob only declares
  # discard_on. Adding retry_on to the shared WebhookJob would change behavior
  # for every core conversation/message webhook. Instead CRM deliveries use the
  # :crm_account_webhook type, for which Trigger RE-RAISES retryable failures
  # (timeout/connection via SafeFetch::FetchError, 5xx via SafeFetch::HttpError),
  # and this job retries them with a bounded backoff. Core webhooks are untouched.
  #
  # EXACTLY-ONCE CAVEAT (plan R4): retry here is per logical delivery attempt.
  # A single logical CRM action can still produce multiple activities (e.g. an
  # AI auto-move emits both ai_auto_moved and move), and at-least-once retry can
  # re-POST the same payload. The stable X-Chatwoot-Event-Id / payload event_id
  # (crm_activities.id) is the consumer-side dedup key — n8n must dedup on it.
  class CrmDeliveryJob < ApplicationJob
    queue_as :low

    # Bounded retry: transient transport/server failures only. After attempts are
    # exhausted the job is dropped (consumer relies on event_id dedup + can be
    # re-driven from a future deliveries table). Non-retryable errors (bad URL,
    # SSRF block) are NOT re-raised by Trigger, so they never reach here.
    retry_on Webhooks::Trigger::RetryableError, wait: :polynomially_longer, attempts: 4

    def perform(url, payload, secret: nil, delivery_id: nil)
      Webhooks::Trigger.execute(url, payload, :crm_account_webhook, secret: secret, delivery_id: delivery_id)
    end
  end
end
