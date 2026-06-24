module Crm
  module Meetings
    # Periodic 2-way sync sweep (S7, PULL): reconciles the imminent, still-scheduled
    # meetings with their provider calendars so a cancellation/reschedule the agent
    # made directly in Google/Outlook is reflected in the CRM even if nobody opens the
    # card. Bounded to the next WINDOW + a hard BATCH_LIMIT so the per-run provider API
    # volume stays sane. Gated by the meetings flag (and an ENV kill-switch). Each
    # meeting is handled best-effort by SyncService (never raises).
    class SyncSweepJob < ApplicationJob
      queue_as :scheduled_jobs

      WINDOW = 7.days
      BATCH_LIMIT = 500

      def perform
        return unless Crm::Config.calendar_meetings_enabled?
        # Kill-switch (default ON). Robust boolean cast so FALSE/0/no/off all disable it.
        return unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_CALENDAR_SYNC_ENABLED', true))

        due_meetings.each do |meeting|
          Crm::Meetings::SyncService.new(meeting: meeting).perform
        end
      end

      private

      def due_meetings
        Crm::Meeting
          .where(status: :scheduled)
          .where.not(external_event_id: nil)
          .where('external_event_id NOT LIKE ?', 'sim-%')
          .where('starts_at > ? AND starts_at < ?', Time.current, Time.current + WINDOW)
          .order(:starts_at)
          .limit(BATCH_LIMIT)
      end
    end
  end
end
