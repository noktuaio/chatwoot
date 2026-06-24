class Crm::Activity < ApplicationRecord
  self.table_name = 'crm_activities'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :conversation, optional: true

  validates :event_type, presence: true
  validates :payload, jsonb_attributes_length: true
  validate :linked_records_must_belong_to_account

  after_commit :emit_webhook_event, on: :create

  private

  # Bridge CRM lifecycle activities to outbound account webhooks.
  # Runs AFTER the mover/closer/creator transaction commits (plan B2) and hands
  # IDS ONLY to the Emitter — never AR objects — so the listener reloads by id.
  def emit_webhook_event
    Crm::Webhooks::Emitter.emit(
      account_id: account_id,
      card_id: card_id,
      activity_id: id,
      event_type: event_type,
      changed_attributes: payload
    )
  end

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
