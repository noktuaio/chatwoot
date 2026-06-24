class EmailSuppression < ApplicationRecord
  belongs_to :account

  REASONS = %w[hard_bounce complaint unsubscribe manual].freeze
  SOURCES = %w[ses api import manual].freeze

  before_validation :normalize_email
  before_create :set_created_at

  validates :email, presence: true, format: { with: EmailCampaign::EMAIL_REGEX }
  validates :email, uniqueness: { scope: :account_id, case_sensitive: false }

  # Returns a downcased Set of suppressed emails for an account (DeliveryJob preload).
  def self.suppressed_set_for(account)
    where(account_id: account.id).pluck(:email).map(&:downcase).to_set
  end

  def self.suppressed?(account, email)
    where(account_id: account.id).where('lower(email) = ?', email.to_s.downcase).exists?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def set_created_at
    self.created_at ||= Time.current
  end
end
