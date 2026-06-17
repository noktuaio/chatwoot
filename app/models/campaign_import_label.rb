class CampaignImportLabel < ApplicationRecord
  belongs_to :campaign_import
  belongs_to :label, optional: true

  enum kind: { base: 0, batch: 1 }, _prefix: true

  validates :title, presence: true
end
