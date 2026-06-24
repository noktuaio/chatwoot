# Public push-notification receiver for the 2-way calendar sync (S7-B). NO auth /
# NO CSRF — the provider POSTs here. The notification is only a TRIGGER: we verify it
# belongs to a subscription WE created (channel/subscription id + shared secret), then
# enqueue a re-sync of that mailbox's meetings through the authenticated SyncService.
# The payload is never trusted for data, so a forged request can at most trigger a
# re-sync of an already-known mailbox (no injection, no cross-tenant access).
class Webhooks::CrmCalendarController < ActionController::API
  # POST /webhooks/crm_calendar/google
  # Google sends X-Goog-Channel-ID / -Channel-Token / -Resource-State headers.
  def google
    state = Crm::CalendarSyncState.google.status_active.find_by(channel_id: request.headers['X-Goog-Channel-ID'])

    if webhooks_enabled? && state && secure_compare(state.verification_token, request.headers['X-Goog-Channel-Token'])
      # 'sync' is the initial channel-created handshake — acknowledge, do no work.
      unless request.headers['X-Goog-Resource-State'].to_s == 'sync'
        state.update_column(:last_notified_at, Time.current)
        Crm::Calendar::WebhookSyncJob.perform_later(state.inbox_id)
      end
    end

    # Always 200 — an unknown channel is a silent no-op (never leak, never trigger
    # Google's aggressive retry on non-2xx).
    head :ok
  end

  # POST /webhooks/crm_calendar/microsoft
  # Graph first POSTs a validation handshake (?validationToken=...) we must echo as
  # text/plain; subsequent calls carry { value: [{ subscriptionId, clientState, ... }] }.
  def microsoft
    if params[:validationToken].present?
      render plain: params[:validationToken].to_s, content_type: 'text/plain', status: :ok
      return
    end

    if webhooks_enabled?
      Array(params[:value]).each do |notification|
        state = Crm::CalendarSyncState.microsoft.status_active.find_by(channel_id: notification['subscriptionId'])
        next unless state && secure_compare(state.verification_token, notification['clientState'])

        state.update_column(:last_notified_at, Time.current)
        Crm::Calendar::WebhookSyncJob.perform_later(state.inbox_id)
      end
    end

    head :accepted
  end

  private

  def secure_compare(expected, given)
    expected.present? && given.present? &&
      ActiveSupport::SecurityUtils.secure_compare(expected.to_s, given.to_s)
  end

  # Same kill-switch as the renewal job — when webhooks are off we acknowledge the
  # provider (200/202, and still answer the MS validation handshake) but do no work.
  def webhooks_enabled?
    Crm::Config.calendar_meetings_enabled? &&
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_CALENDAR_WEBHOOKS_ENABLED', false))
  end
end
