class Crm::Conversations::SyncLock
  def initialize(account:, conversation:)
    @account = account
    @conversation = conversation
  end

  def perform(&)
    @conversation.with_lock do
      @conversation.reload
      contact = @conversation.contact_id.present? ? @account.contacts.find_by(id: @conversation.contact_id) : nil
      if contact.present?
        contact.with_lock(&)
      else
        yield
      end
    end
  end
end
