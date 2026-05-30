module Enterprise::Campaign
  extend ActiveSupport::Concern

  included do
    has_many :campaign_deliveries, dependent: :destroy
  end
end
