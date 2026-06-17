module EmailCampaigns
  module Unsubscribe
    # Signed unsubscribe tokens (Onda D real unsubscribe). Mirrors Tracking::Token: dedicated
    # message_verifier, URL-safe Base64 wrap so the token survives a bare :token route segment,
    # and the same tracking base_url fallback. A tampered token fails verify -> nil.
    module Token
      module_function

      def verifier
        Rails.application.message_verifier(:email_campaign_unsubscribe)
      end

      def encode(recipient)
        verifier.generate({ r: recipient.id, k: 'u' }, purpose: :email_unsubscribe)
      end

      def decode(token)
        verifier.verify(unwrap(token), purpose: :email_unsubscribe)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage,
             ArgumentError
        nil
      end

      # Same rationale as Tracking::Token#wrap: message_verifier emits strict Base64 ('/' '+' '=')
      # which breaks a :token path segment; wrap in URL-safe Base64 without padding.
      def wrap(token)
        Base64.urlsafe_encode64(token, padding: false)
      end

      def unwrap(token)
        Base64.urlsafe_decode64(token.to_s)
      end

      def base_url
        ENV.fetch('EMAIL_CAMPAIGN_TRACKING_BASE_URL', nil).presence ||
          ENV.fetch('FRONTEND_URL', 'https://app.chatwoot.com')
      end

      def url(recipient)
        "#{base_url}/email_campaigns/u/#{wrap(encode(recipient))}"
      end
    end
  end
end
