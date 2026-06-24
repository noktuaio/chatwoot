class WhatsappApiCampaignRecipient < ApplicationRecord
  belongs_to :whatsapp_api_campaign
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true

  enum status: {
    pending: 0,
    sending: 1,
    sent: 2,
    failed: 3,
    cancelled: 4
  }

  validates :account_id, :inbox_id, :contact_id, presence: true
  validate :associations_must_match_campaign

  def mark_failed!(message)
    update!(
      status: :failed,
      last_error_message: message.to_s.truncate(500),
      failed_at: Time.current
    )
  end

  private

  def associations_must_match_campaign
    return unless whatsapp_api_campaign

    errors.add(:account_id, 'must match campaign') if account_id != whatsapp_api_campaign.account_id
    errors.add(:inbox_id, 'must match campaign') if inbox_id != whatsapp_api_campaign.inbox_id
  end
end
