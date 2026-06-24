class Crm::CardConversation < ApplicationRecord
  self.table_name = 'crm_card_conversations'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :conversation
  belongs_to :linked_by, class_name: 'User', optional: true

  validates :conversation_id, uniqueness: { scope: [:account_id, :card_id] }
  validate :linked_records_must_belong_to_account

  private

  def linked_records_must_belong_to_account
    validate_same_account(:card)
    validate_same_account(:conversation)
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
