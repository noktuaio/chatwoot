module EmailCampaigns
  module Ses
    # Sends a single email through SES from a verified sender identity. Powers the human
    # smoke test now and campaign delivery in later waves. Returns the SES MessageId.
    class Sender
      def initialize(identity)
        @identity = identity
        @client = Client.new
      end

      def deliver(to:, subject:, html_body:, text_body: nil, from_email: nil, reply_to: nil, headers: nil)
        raise Error, "identity #{@identity.domain} is not verified" unless @identity.usable?

        response = @client.send_email(
          from: resolve_from(from_email), to: to, subject: subject,
          html_body: html_body, text_body: text_body, reply_to: reply_to,
          configuration_set: @identity.ses_configuration_set, headers: headers
        )
        response['MessageId']
      end

      private

      def resolve_from(from_email)
        from_email.presence || @identity.from_email.presence || "no-reply@#{@identity.domain}"
      end
    end
  end
end
