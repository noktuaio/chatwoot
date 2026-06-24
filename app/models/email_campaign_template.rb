class EmailCampaignTemplate < ApplicationRecord
  # account is optional: account_id IS NULL marks a GLOBAL gallery template shared with every account.
  belongs_to :account, optional: true

  # Real compiled email HTML/MJML easily exceeds ApplicationRecord's global 20k text cap;
  # declare an explicit (generous) limit so the global guard skips these columns.
  BODY_MAX = 500_000

  validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :body_html, length: { maximum: BODY_MAX }
  validates :body_mjml, length: { maximum: BODY_MAX }

  scope :by_category, ->(category) { where(category: category) if category.present? }
  scope :global, -> { where(account_id: nil) }
  scope :for_account, ->(account) { where(account: account).or(global) }
end
