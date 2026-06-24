class Crm::Conversations::DedupReuseLogger
  def initialize(card:, conversation:, reason:, window_days:)
    @card = card
    @conversation = conversation
    @reason = reason
    @window_days = window_days
  end

  def perform
    Crm::ActivityLogger.new(
      card: @card,
      actor: nil,
      event_type: 'conversation_dedup_reuse',
      conversation: @conversation,
      payload: payload
    ).perform
  end

  private

  def payload
    {
      reason: @reason,
      contact_id: @conversation.contact_id,
      inbox_id: @conversation.inbox_id,
      pipeline_id: @card.pipeline_id,
      dedup_window_days: @window_days
    }
  end
end
