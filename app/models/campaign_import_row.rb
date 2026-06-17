class CampaignImportRow < ApplicationRecord
  belongs_to :campaign_import
  belongs_to :contact, optional: true

  enum status: {
    pending: 0,
    valid: 1,
    invalid: 2,
    imported: 3,
    import_failed: 4,
    labels_undone: 5,
    undo_failed: 6
  }, _prefix: true

  validates :row_number, presence: true
end
