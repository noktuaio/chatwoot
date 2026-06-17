module Crm
  module Ai
    class CredentialResolver
      def initialize(account:)
        @account = account
      end

      def resolve
        return hook_credential if @account.hooks.account_hooks.exists?(app_id: 'crm_kanban_ai')

        system_credential
      end

      def configured?
        resolve.present?
      end

      private

      def hook_credential
        hook = @account.hooks.enabled.account_hooks.find_by(app_id: 'crm_kanban_ai')
        return if hook.blank?
        return if hook.settings.to_h['enabled'] == false

        api_key = hook.settings.to_h['api_key'].presence
        return if api_key.blank?

        {
          api_key: api_key,
          api_base: hook.settings.to_h['api_base'].presence || default_api_base,
          source: :hook
        }
      end

      def system_credential
        api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence
        return if api_key.blank?

        endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || default_api_base
        {
          api_key: api_key,
          api_base: endpoint.chomp('/'),
          source: :system
        }
      end

      def default_api_base
        'https://api.openai.com'
      end
    end
  end
end
