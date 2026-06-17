class Crm::SyncConversationCardJob < ApplicationJob
  queue_as :low

  def perform(conversation_id, message_id = nil)
    return unless Crm::Config.enabled?

    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    message = Message.find_by(id: message_id) if message_id.present?
    Crm::Conversations::CardSyncer.new(conversation: conversation, message: message).perform
  end
end
