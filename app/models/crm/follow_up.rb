class Crm::FollowUp < ApplicationRecord
  self.table_name = 'crm_follow_ups'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
  belongs_to :inbox, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  enum follow_up_type: { task: 0, message: 1, call: 2, meeting: 3, note: 4 }
  enum status: { pending: 0, done: 1, canceled: 2, overdue: 3 }
  enum automation_mode: { reminder_only: 0, snooze_conversation: 1, auto_send_message: 2 }

  validates :title, :due_at, :timezone, presence: true
  validates :metadata, jsonb_attributes_length: true
  validate :linked_records_must_belong_to_account
  validate :snooze_requires_conversation
  validate :auto_send_requirements

  scope :active, -> { where(status: [statuses[:pending], statuses[:overdue]]) }
  scope :due, ->(time = Time.current) { pending.where(due_at: ..time) }

  private

  def snooze_requires_conversation
    return unless snooze_conversation?
    return if conversation_id.present?

    errors.add(:conversation, 'is required for snooze follow-ups')
  end

  def auto_send_requirements
    return unless auto_send_message?

    Crm::FollowUps::AutoSendValidator.new(self).validate
  end

  def linked_records_must_belong_to_account
    validate_same_account(:card)
    validate_same_account(:conversation)
    validate_same_account(:contact)
    validate_same_account(:inbox)
    validate_assignee_account
    validate_created_by_account
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end

  def validate_assignee_account
    return if assignee.blank? || account_id.blank?
    return if assignee.account_users.exists?(account_id: account_id)

    errors.add(:assignee, 'must belong to the same account')
  end

  def validate_created_by_account
    return if created_by.blank? || account_id.blank?
    return if created_by.account_users.exists?(account_id: account_id)

    errors.add(:created_by, 'must belong to the same account')
  end
end
