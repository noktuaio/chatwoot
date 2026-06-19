class Crm::Kanban::CardPayloadBuilder
  def initialize(card:, conversation_visibility:, pending_suggestion: nil)
    @card = card
    @conversation_visibility = conversation_visibility
    @pending_suggestion = pending_suggestion
  end

  def perform
    identity_payload.merge(status_payload, link_payload)
  end

  private

  def identity_payload
    {
      id: @card.id,
      title: @card.title,
      pipeline_id: @card.pipeline_id,
      stage_id: @card.stage_id,
      contact_id: @card.contact_id,
      conversation_id: visible_primary_conversation&.id,
      inbox_id: @card.inbox_id,
      owner_id: @card.owner_id,
      team_id: @card.team_id
    }
  end

  def status_payload
    {
      value_cents: @card.value_cents,
      currency: @card.currency,
      priority: @card.priority,
      score: @card.score,
      status: @card.status,
      is_standalone: @card.standalone?,
      # Epoch seconds across the board payload so the frontend timeHelper.js
      # (fromUnixTime-based) renders them consistently without Invalid-Date.
      next_follow_up_at: @card.next_follow_up_at&.to_i,
      next_follow_up_source: next_follow_up_source,
      last_message_at: @card.last_message_at&.to_i,
      entered_stage_at: @card.entered_stage_at&.to_i,
      ai_suggestion: ai_suggestion_payload
    }.compact
  end

  # Type of the follow-up that owns next_follow_up_at (the nearest active one) so
  # the card badge can show 🤖 (AI cadence) vs 🔔 (manual reminder) WITHOUT a
  # per-card query: the nearest is the AI touch iff the active cadence's
  # next_due_at equals next_follow_up_at; otherwise it is a manual/other follow-up.
  def next_follow_up_source
    return if @card.next_follow_up_at.blank?

    state = (@card.metadata || {}).dig('ai', 'auto_followup_state') || {}
    return 'manual' unless state['active'] == true && state['next_due_at'].present?

    Time.zone.parse(state['next_due_at'].to_s).to_i == @card.next_follow_up_at.to_i ? 'ai' : 'manual'
  rescue ArgumentError, TypeError
    'manual'
  end

  def ai_suggestion_payload
    return unless Crm::Ai::Config.enabled?

    suggestion = @pending_suggestion || @card.ai_stage_suggestions.current_pending.includes(:to_stage).first
    return if suggestion.blank?

    {
      id: suggestion.id,
      to_stage_id: suggestion.to_stage_id,
      to_stage_name: suggestion.to_stage&.name,
      confidence: suggestion.confidence.to_f
    }
  end

  def link_payload
    {
      contact: compact_contact,
      owner: compact_user(@card.owner),
      responsible: @card.responsible_descriptor,
      inbox: compact_inbox,
      conversation: compact_conversation
    }
  end

  def compact_contact
    return if @card.contact.blank?

    {
      id: @card.contact.id,
      name: @card.contact.name,
      phone_number: @card.contact.phone_number
    }
  end

  def compact_user(user)
    return if user.blank?

    { id: user.id, name: user.name }
  end

  def compact_inbox
    return if @card.inbox.blank?

    {
      id: @card.inbox.id,
      name: @card.inbox.name,
      channel_type: @card.inbox.channel_type
    }
  end

  def compact_conversation
    conversation = visible_primary_conversation
    return if conversation.blank?

    payload = {
      id: conversation.id,
      display_id: conversation.display_id,
      inbox_id: conversation.inbox_id,
      status: conversation.status,
      first_reply_created_at: conversation.first_reply_created_at&.to_i,
      waiting_since: conversation.waiting_since&.to_i
    }
    applied_sla = applied_sla_payload(conversation)
    payload[:applied_sla] = applied_sla if applied_sla.present?
    payload
  end

  # SLA badge data for the board feed; mirrors Crm::Cards::PayloadBuilder so the
  # Kanban and List views agree. Gated on the account 'sla' feature.
  def applied_sla_payload(conversation)
    return unless @card.account.feature_enabled?('sla')
    return unless conversation.class.reflect_on_association(:applied_sla)

    conversation.applied_sla&.push_event_data
  end

  def visible_primary_conversation
    conversation = @card.primary_conversation
    return if conversation.blank?
    return conversation if @conversation_visibility.visible?(conversation)

    nil
  end
end
