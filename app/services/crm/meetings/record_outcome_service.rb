class Crm::Meetings::RecordOutcomeService
  VALID_OUTCOMES = %w[held no_show].freeze
  MAX_NOTES_LENGTH = 5000

  def initialize(meeting:, outcome:, notes: nil)
    @meeting = meeting
    @outcome = outcome.to_s
    @notes = notes
  end

  def perform
    raise ArgumentError, 'invalid_outcome' unless VALID_OUTCOMES.include?(@outcome)
    # Outcome is CRM-internal (no calendar-provider call), so it is provider
    # agnostic and behaves identically for Google and Microsoft meetings.
    raise ArgumentError, 'meeting_not_active' unless @meeting.scheduled?
    # Server-side guard: an outcome can only be recorded after the meeting has
    # actually finished. The FE hides the prompt for future meetings, but the
    # API must enforce it too (no marking a next-week meeting as no-show today).
    raise ArgumentError, 'meeting_not_finished' unless @meeting.ends_at.present? && @meeting.ends_at <= Time.current

    @meeting.update!(
      outcome: @outcome,
      outcome_notes: sanitized_notes,
      outcome_recorded_at: Time.current
    )

    log_activity
    @meeting
  end

  private

  def sanitized_notes
    return if @notes.blank?

    # Strip HTML tags + control chars (defense-in-depth, mirrors the meeting
    # description sanitizer) before storing — notes are shown in the card and
    # later fed to the AI summary (S5).
    ActionController::Base.helpers.strip_tags(@notes.to_s)
                          .gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, '')
                          .strip.truncate(MAX_NOTES_LENGTH)
  end

  def log_activity
    Crm::ActivityLogger.new(
      card: @meeting.card,
      actor: @meeting.created_by,
      event_type: 'meeting_outcome_recorded',
      conversation: @meeting.card.primary_conversation,
      payload: {
        meeting_id: @meeting.id,
        outcome: @meeting.outcome,
        title: @meeting.title
      }
    ).perform
  end
end
