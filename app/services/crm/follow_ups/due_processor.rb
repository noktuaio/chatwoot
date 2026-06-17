class Crm::FollowUps::DueProcessor
  def initialize(now: Time.current)
    @now = now
  end

  def perform
    Crm::FollowUp.due(@now).find_each { |follow_up| process(follow_up) }
  end

  private

  def process(follow_up)
    follow_up.with_lock do
      next unless follow_up.pending? && follow_up.due_at <= @now

      if follow_up.auto_send_message? && ai_followup?(follow_up)
        process_ai_followup(follow_up)
      elsif follow_up.auto_send_message?
        process_auto_send(follow_up)
      else
        process_overdue(follow_up)
      end
    end
  end

  def ai_followup?(follow_up)
    follow_up.metadata.to_h['source'] == 'ai_followup'
  end

  # Isolated branch for AI auto-follow-up touches. Delegates the whole per-touch
  # decision (auto-stop gates, compose, window, cap, send, schedule next) to
  # Crm::FollowUps::AutoFollowupRunner, then maps its Result onto this follow_up's
  # final status exactly like process_auto_send does. process_auto_send /
  # process_overdue stay byte-for-byte unchanged for manual + stage automations.
  def process_ai_followup(follow_up)
    result = Crm::FollowUps::AutoFollowupRunner.new(follow_up: follow_up, now: @now).perform

    case result.status
    when :sent
      follow_up.update!(status: :done, completed_at: @now)
      log_message_sent(follow_up, follow_up.conversation&.messages&.find_by(id: follow_up.metadata.to_h['sent_message_id']))
    when :stopped, :skipped
      follow_up.update!(status: :done, completed_at: @now)
    when :rescheduled
      # Marketing-cap deferral: the runner pushed this SAME touch's due_at into the
      # future. Leave it pending so the next due sweep re-runs it once the cap clears.
    when :failed
      # TRANSIENT compose/send failure under the retry budget. Mirror :rescheduled:
      # keep the follow_up PENDING and bump due_at to the runner's retry_at so the
      # next due sweep re-runs the SAME touch (the `due` scope is pending-only, so an
      # :overdue touch would strand the cadence forever). The runner owns the bounded
      # retry counter; here we only re-arm the row.
      follow_up.update!(
        due_at: result.retry_at,
        metadata: follow_up.metadata.merge('send_error' => result.error.to_s)
      )
      log_message_failed(follow_up, result.error)
    when :failed_final
      # Retry budget exhausted. The runner already finalized the cadence state
      # (active:false, stopped_reason:'send_failed') and canceled siblings, so we just
      # close this touch out as done — letting the planner eventually re-evaluate the card.
      follow_up.update!(
        status: :done,
        completed_at: @now,
        metadata: follow_up.metadata.merge('send_error' => result.error.to_s)
      )
      log_message_failed(follow_up, result.error)
    end

    finalize_follow_up(follow_up)
  end

  def process_auto_send(follow_up)
    result = Crm::FollowUps::MessageSender.new(follow_up: follow_up).perform

    case result.status
    when :sent
      follow_up.update!(status: :done, completed_at: @now)
      log_message_sent(follow_up, result.message)
    when :skipped
      complete_already_sent_follow_up(follow_up)
    when :failed
      follow_up.update!(
        status: :overdue,
        metadata: follow_up.metadata.merge('send_error' => result.error.to_s)
      )
      log_message_failed(follow_up, result.error)
    end

    finalize_follow_up(follow_up)
  end

  def complete_already_sent_follow_up(follow_up)
    return if follow_up.metadata.to_h['sent_message_id'].blank?
    return if follow_up.done?

    follow_up.update!(status: :done, completed_at: @now)
  end

  def process_overdue(follow_up)
    follow_up.update!(status: :overdue)
    reopen_conversation(follow_up)
    log_overdue(follow_up)
    notify_reminder_due(follow_up)
    finalize_follow_up(follow_up)
  end

  def notify_reminder_due(follow_up)
    Crm::FollowUps::Broadcaster.broadcast_due(follow_up)
  end

  def finalize_follow_up(follow_up)
    Crm::FollowUps::CardNextDueUpdater.update(follow_up.card)
    Crm::Cards::Broadcaster.broadcast(follow_up.card, Events::Types::CRM_CARD_UPDATED)
  end

  def reopen_conversation(follow_up)
    return unless follow_up.snooze_conversation?
    return if follow_up.conversation.blank?

    follow_up.conversation.open!
  end

  def log_overdue(follow_up)
    Crm::ActivityLogger.new(
      card: follow_up.card,
      actor: nil,
      event_type: 'follow_up_overdue',
      conversation: follow_up.conversation,
      payload: {
        follow_up_id: follow_up.id,
        automation_mode: follow_up.automation_mode,
        due_at: follow_up.due_at&.iso8601
      }
    ).perform
  end

  def log_message_sent(follow_up, message)
    Crm::ActivityLogger.new(
      card: follow_up.card,
      actor: nil,
      event_type: 'follow_up_message_sent',
      conversation: follow_up.conversation,
      payload: {
        follow_up_id: follow_up.id,
        message_id: message&.id,
        send_mode: follow_up.metadata.to_h['send_mode'],
        due_at: follow_up.due_at&.iso8601
      }
    ).perform
  end

  def log_message_failed(follow_up, error)
    Crm::ActivityLogger.new(
      card: follow_up.card,
      actor: nil,
      event_type: 'follow_up_message_failed',
      conversation: follow_up.conversation,
      payload: {
        follow_up_id: follow_up.id,
        error: error.to_s,
        due_at: follow_up.due_at&.iso8601
      }
    ).perform
  end
end
