class EmailSenderIdentity < ApplicationRecord
  belongs_to :account

  enum status: { pending: 0, verifying: 1, verified: 2, failed: 3 }

  DOMAIN_REGEX = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/i

  before_validation :normalize_domain

  validates :domain, presence: true, format: { with: DOMAIN_REGEX }
  validates :domain, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :provider, presence: true

  scope :verified_identities, -> { where(status: :verified) }
  scope :pending_verification, -> { where(status: %i[pending verifying]) }

  def usable?
    verified?
  end

  private

  def normalize_domain
    self.domain = domain.to_s.strip.downcase.presence
  end
end
