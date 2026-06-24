class Crm::ConversationObserverListener < BaseListener
  def message_created(event)
    return unless Crm::Config.enabled?

    message = event.data[:message]
    return if ignored_message?(message)

    Crm::SyncConversationCardJob.perform_later(message.conversation_id, message.id)
  end

  # SLA auto-apply v1 (gatilho "conversa criada"): hand off to a job so listener
  # stays fast; all gating (feature flag, policy match, groups) lives in the job.
  def conversation_created(event)
    return unless Crm::Config.enabled?

    conversation, = extract_conversation_and_account(event)
    return if conversation&.id.blank?

    Crm::SlaAutoApplyJob.perform_later(conversation.id)
  end

  # Keep the card's real-time "responsible" in sync when the conversation is
  # (un)assigned: re-sync the card (mirrors owner, re-broadcasts to the board).
  def assignee_changed(event)
    return unless Crm::Config.enabled?

    conversation, = extract_conversation_and_account(event)
    return if conversation&.id.blank?

    Crm::SyncConversationCardJob.perform_later(conversation.id)
  end

  # Keep the card's team in sync on a team-only reassignment (e.g. an Autonomia
  # native-agent handoff with strategy 'assign_team', which updates team without
  # touching the assignee). Without this, a team change never enqueues a card
  # sync and the card's team_id lags. Mirrors assignee_changed; same idempotent
  # job; purely additive (assignee/message paths unchanged).
  def team_changed(event)
    return unless Crm::Config.enabled?

    conversation, = extract_conversation_and_account(event)
    return if conversation&.id.blank?

    Crm::SyncConversationCardJob.perform_later(conversation.id)
  end

  private

  def ignored_message?(message)
    message.blank? ||
      message.conversation_id.blank? ||
      message.activity? ||
      message.private?
  end
end
