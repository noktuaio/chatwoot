class Crm::FollowUps::SnoozeHandler
  def self.apply(follow_up)
    new(follow_up).perform
  end

  def initialize(follow_up)
    @follow_up = follow_up
  end

  def perform
    return unless @follow_up.snooze_conversation?
    return if @follow_up.conversation.blank?

    @follow_up.conversation.update!(
      status: :snoozed,
      snoozed_until: @follow_up.due_at
    )
  end
end
