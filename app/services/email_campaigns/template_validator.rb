module EmailCampaigns
  # Compares the {{ tokens }} used in a campaign's subject/preheader/body against
  # the placeholders available for it (defaults + imported custom_data keys).
  class TemplateValidator
    DEFAULT_KEYS = %w[nome email contact.name contact.email unsubscribe_url].freeze
    TOKEN_REGEX = /\{\{-?\s*([a-zA-Z0-9_.]+)/

    def initialize(campaign)
      @campaign = campaign
    end

    def available
      DEFAULT_KEYS + custom_keys
    end

    def perform
      used = used_keys
      {
        available: available,
        used: used,
        missing: used - available,
        blank_counts: blank_counts(used & custom_keys)
      }
    end

    private

    def custom_keys
      @custom_keys ||= @campaign.email_campaign_recipients
                                .pluck(Arel.sql('DISTINCT jsonb_object_keys(custom_data)'))
                                .sort
    end

    def used_keys
      [@campaign.subject, @campaign.preheader, @campaign.body_mjml.presence || @campaign.body_html]
        .compact.join("\n").scan(TOKEN_REGEX).flatten.uniq
    end

    def blank_counts(keys)
      keys.index_with do |key|
        @campaign.email_campaign_recipients.where("COALESCE(custom_data->>?, '') = ''", key).count
      end
    end
  end
end
