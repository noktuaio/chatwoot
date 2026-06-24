class WhatsappApiCampaign < ApplicationRecord
  attr_accessor :media_file_pending

  belongs_to :account
  belongs_to :inbox
  belongs_to :created_by, class_name: 'User'
  belongs_to :whatsapp_api_message_template, optional: true

  has_many :whatsapp_api_campaign_recipients, dependent: :destroy
  has_one_attached :media_file

  enum status: {
    scheduled: 0,
    running: 1,
    paused: 2,
    completed: 3,
    completed_with_failures: 4,
    cancelled: 5,
    failed: 6
  }

  validates :title, presence: true, length: { maximum: 120 }
  validates :audience, presence: true
  validates :scheduled_at, presence: true
  validate :inbox_must_belong_to_account
  validate :created_by_must_belong_to_account
  validate :inbox_must_be_whatsapp_api_campaign_channel
  validate :message_or_media_required
  validate :message_variables_must_be_supported

  def terminal?
    completed? || completed_with_failures? || cancelled? || failed?
  end

  def pause!
    return if terminal? || paused?

    update!(status: :paused, paused_at: Time.current)
  end

  def resume!
    return unless paused?

    update!(status: :running, resumed_at: Time.current)
    WhatsappApiCampaigns::DeliveryJob.perform_later(id) if WhatsappApiCampaigns::Config.enabled?
  end

  def cancel!
    return if terminal?

    with_lock do
      update!(status: :cancelled, cancelled_at: Time.current)
      whatsapp_api_campaign_recipients.where(status: %i[pending sending]).update_all(status: WhatsappApiCampaignRecipient.statuses[:cancelled],
                                                                                     cancelled_at: Time.current,
                                                                                     updated_at: Time.current)
      refresh_counters!
    end
  end

  def refresh_counters!
    counts = whatsapp_api_campaign_recipients.group(:status).count
    update_columns(
      recipients_count: counts.values.sum,
      sent_count: count_for_status(counts, 'sent'),
      failed_count: count_for_status(counts, 'failed'),
      cancelled_count: count_for_status(counts, 'cancelled'),
      updated_at: Time.current
    )
  end

  private

  def count_for_status(counts, status_name)
    counts.fetch(status_name, counts.fetch(WhatsappApiCampaignRecipient.statuses[status_name], 0))
  end

  def inbox_must_belong_to_account
    return unless inbox
    return if inbox.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account')
  end

  def created_by_must_belong_to_account
    return unless created_by
    return if account&.users&.exists?(id: created_by.id)

    errors.add(:created_by_id, 'must belong to the same account')
  end

  def inbox_must_be_whatsapp_api_campaign_channel
    return unless inbox
    return if inbox.api? && inbox.channel.whatsapp_api_campaign_channel?

    errors.add(:inbox_id, 'must be an API inbox marked for WhatsApp API campaigns')
  end

  def message_or_media_required
    return if message_body.present? || media_file.attached? || media_file_pending

    errors.add(:base, 'message body or media file is required')
  end

  def message_variables_must_be_supported
    unsupported = WhatsappApiCampaigns::TemplateRenderer.unsupported_variables_in(message_body)
    return if unsupported.blank?

    errors.add(:message_body, "has unsupported variables: #{unsupported.join(', ')}")
  end
end
