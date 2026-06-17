class CampaignImport < ApplicationRecord
  DELETABLE_BEFORE_IMPORT_STATUSES = %w[uploaded validation_failed ready_to_confirm failed cancelled expired].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :data_import, optional: true

  has_many :campaign_import_rows, dependent: :destroy
  has_many :campaign_import_labels, dependent: :destroy

  has_one_attached :original_file
  has_one_attached :normalized_csv
  has_one_attached :error_csv
  has_one_attached :report_csv

  enum status: {
    uploaded: 0,
    validating: 1,
    validation_failed: 2,
    ready_to_confirm: 3,
    confirmed: 4,
    queued: 5,
    importing: 6,
    completed: 7,
    completed_with_failures: 8,
    failed: 9,
    cancelled: 10,
    expired: 11,
    undoing_labels: 12,
    labels_undone: 13,
    undo_failed: 14
  }

  enum undo_status: {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }, _prefix: true

  validates :account_id, :user_id, presence: true
  validates :mode, inclusion: { in: %w[single_label batches] }, allow_blank: true

  def downloadable_error_csv?
    error_csv.attached?
  end

  def downloadable_report_csv?
    report_csv.attached?
  end

  def deletable_before_import?
    DELETABLE_BEFORE_IMPORT_STATUSES.include?(status) &&
      imported_contacts_count.zero? &&
      campaign_import_rows.where.not(contact_id: nil).none?
  end

  def base_label
    labels = campaign_import_labels.loaded? ? campaign_import_labels : campaign_import_labels.kind_base
    labels.find { |label| label.kind_base? }&.title
  end
end
