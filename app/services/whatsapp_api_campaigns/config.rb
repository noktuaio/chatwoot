module WhatsappApiCampaigns
  class Config
    BOOLEAN = ActiveModel::Type::Boolean.new

    def self.enabled?
      BOOLEAN.cast(ENV.fetch('WHATSAPP_API_CAMPAIGNS_ENABLED', false))
    end

    def self.min_delay_seconds
      non_negative_integer('WHATSAPP_API_CAMPAIGNS_MIN_DELAY_SECONDS', 3)
    end

    def self.max_delay_seconds
      [non_negative_integer('WHATSAPP_API_CAMPAIGNS_MAX_DELAY_SECONDS', 8), min_delay_seconds].max
    end

    def self.max_attempts
      [non_negative_integer('WHATSAPP_API_CAMPAIGNS_MAX_ATTEMPTS', 3), 1].max
    end

    def self.max_media_size_bytes
      [non_negative_integer('WHATSAPP_API_CAMPAIGNS_MAX_MEDIA_MB', 16), 1].max.megabytes
    end

    def self.sending_stale_after_seconds
      [non_negative_integer('WHATSAPP_API_CAMPAIGNS_SENDING_STALE_AFTER_SECONDS', 15.minutes.to_i), 60].max
    end

    def self.random_delay_seconds
      rand(min_delay_seconds..max_delay_seconds)
    end

    def self.non_negative_integer(key, fallback)
      Integer(ENV.fetch(key, fallback))
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
