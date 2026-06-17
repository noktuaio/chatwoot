module EmailCampaigns
  module Ses
    # Idempotently ensures the SES configuration set exists (AlreadyExists treated as ok).
    # Used now for later event publishing; provisioning calls it best-effort.
    class ConfigurationSetEnsurer
      def perform(name = EmailCampaigns::Config.configuration_set_name)
        Client.new.create_configuration_set(name)
        name
      end
    end
  end
end
