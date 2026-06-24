class Sla::ScheduleResolver
  # Calendar precedence (LOCKED): CURRENT assigned agent at evaluation time,
  # else the conversation inbox, else nil (callers fall back to 24/7 wall clock).
  # Lookups are account-scoped.
  def self.for_conversation(conversation)
    if conversation.assignee_id.present?
      schedule = Crm::ServiceSchedule.find_by(account_id: conversation.account_id, owner_type: 'User', owner_id: conversation.assignee_id)
      return schedule if schedule&.usable?
    end

    schedule = Crm::ServiceSchedule.find_by(account_id: conversation.account_id, owner_type: 'Inbox', owner_id: conversation.inbox_id)
    schedule&.usable? ? schedule : nil
  end
end
