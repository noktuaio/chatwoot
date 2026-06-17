module EmailCampaigns
  module Tracking
    # Signed tracking tokens (own tracking, listmonk/Postal style). Reuses the Rails
    # message_verifier family like Onda 2 DeliveryConfig. Two flavors: open (recipient id)
    # and click (recipient id + the validated http/https original url). A tampered token
    # fails verify -> nil -> no open redirect possible.
    module Token
      module_function

      def verifier
        Rails.application.message_verifier(:email_campaign_tracking)
      end

      def encode_open(recipient)
        verifier.generate({ r: recipient.id, k: 'o' }, purpose: :email_open)
      end

      def encode_click(recipient, url)
        verifier.generate({ r: recipient.id, u: url, k: 'c' }, purpose: :email_click)
      end

      def decode_open(token)
        decode(token, :email_open)
      end

      def decode_click(token)
        decode(token, :email_click)
      end

      def decode(token, purpose)
        verifier.verify(unwrap(token), purpose: purpose)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage,
             ArgumentError
        nil
      end

      # The Rails message_verifier token uses the strict Base64 alphabet (emits '/', '+', '=')
      # which is NOT safe in a bare :token route segment (matcher [^/.?]+): a '/' truncates the
      # capture -> 404. Wrap the whole token in URL-safe Base64 (alphabet -_ , no '=' padding) so
      # the path segment is always route-safe end-to-end, and unwrap before verify.
      def wrap(token)
        Base64.urlsafe_encode64(token, padding: false)
      end

      def unwrap(token)
        Base64.urlsafe_decode64(token.to_s)
      end

      # tracking base url: ENV override else FRONTEND_URL (PRD §3 own tracking domain).
      def base_url
        ENV.fetch('EMAIL_CAMPAIGN_TRACKING_BASE_URL', nil).presence ||
          ENV.fetch('FRONTEND_URL', 'https://app.chatwoot.com')
      end

      # NOTE: no .gif suffix (route uses defaults: { format: 'gif' }; J integration contract).
      def open_url(recipient)
        "#{base_url}/email_campaigns/t/o/#{wrap(encode_open(recipient))}"
      end

      def click_url(recipient, url)
        "#{base_url}/email_campaigns/t/c/#{wrap(encode_click(recipient, url))}"
      end
    end
  end
end
