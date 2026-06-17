module EmailCampaigns
  class Config
    BOOLEAN = ActiveModel::Type::Boolean.new

    DEFAULT_REGION = 'sa-east-1'.freeze
    CONFIGURATION_SET_NAME = 'autonomia-email-campaigns'.freeze

    def self.enabled?
      ::Crm::Config.enabled? && BOOLEAN.cast(ENV.fetch('EMAIL_CAMPAIGN_ENABLED', false))
    end

    def self.region
      ENV.fetch('EMAIL_CAMPAIGN_AWS_REGION', nil).presence ||
        ENV.fetch('AWS_REGION', nil).presence ||
        DEFAULT_REGION
    end

    def self.access_key_id
      ENV.fetch('EMAIL_CAMPAIGN_AWS_ACCESS_KEY_ID', nil).presence ||
        ENV.fetch('AWS_ACCESS_KEY_ID', '')
    end

    def self.secret_access_key
      ENV.fetch('EMAIL_CAMPAIGN_AWS_SECRET_ACCESS_KEY', nil).presence ||
        ENV.fetch('AWS_SECRET_ACCESS_KEY', '')
    end

    def self.configuration_set_name
      ENV.fetch('EMAIL_CAMPAIGN_SES_CONFIGURATION_SET', CONFIGURATION_SET_NAME)
    end
  end
end
