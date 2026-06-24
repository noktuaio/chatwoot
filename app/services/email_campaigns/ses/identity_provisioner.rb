module EmailCampaigns
  module Ses
    # Provisions a SES Easy DKIM domain identity for a persisted EmailSenderIdentity:
    # creates the identity, derives DNS records (DKIM CNAMEs + recommended SPF/DMARC) and
    # flips the record to :verifying. Idempotent against re-runs (AlreadyExists path).
    class IdentityProvisioner
      SPF_RECORD = 'v=spf1 include:amazonses.com ~all'.freeze
      DMARC_RECORD = 'v=DMARC1; p=none;'.freeze

      def initialize(identity)
        @identity = identity
        @client = Client.new
      end

      def perform
        ensure_configuration_set
        tokens = dkim_tokens
        @identity.update!(
          dkim_records: build_dkim_records(tokens), spf_record: SPF_RECORD, dmarc_record: DMARC_RECORD,
          status: :verifying, ses_configuration_set: EmailCampaigns::Config.configuration_set_name,
          last_error: nil
        )
      rescue Error => e
        @identity.update!(status: :failed, last_error: e.message.to_s.truncate(255))
        raise
      end

      private

      def dkim_tokens
        response = @client.create_email_identity(@identity.domain)
        response = @client.get_email_identity(@identity.domain) if response.blank?
        Array(response.dig('DkimAttributes', 'Tokens'))
      end

      def build_dkim_records(tokens)
        tokens.map do |token|
          {
            'type' => 'CNAME',
            'name' => "#{token}._domainkey.#{@identity.domain}",
            'value' => "#{token}.dkim.amazonses.com"
          }
        end
      end

      def ensure_configuration_set
        ConfigurationSetEnsurer.new.perform
      rescue Error => e
        Rails.logger.warn("[EmailCampaigns] configuration set ensure failed: #{e.message}")
      end
    end
  end
end
