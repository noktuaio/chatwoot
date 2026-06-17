class EmailEvent < ApplicationRecord
  belongs_to :recipient, class_name: 'EmailCampaignRecipient'

  enum event_type: {
    delivered: 0, open: 1, click: 2, bounce: 3, complaint: 4, unsubscribe: 5
  }

  validates :occurred_at, presence: true

  scope :opens, -> { where(event_type: :open) }
  scope :clicks, -> { where(event_type: :click) }

  before_validation { self.occurred_at ||= Time.current }
end
