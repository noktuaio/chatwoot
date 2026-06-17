require 'ostruct'

module EmailCampaigns
  module DirectInbox
    # Envia 1 e-mail pela PRÓPRIA caixa conectada (sem SES). Mesma interface do Ses::Sender.
    # Microsoft -> Graph /sendMail; Google -> SMTP gmail XOAUTH2; genérico -> SMTP do canal.
    # É o mesmo "motor" das respostas 1:1, então o envio é legítimo (passa SPF/DKIM/DMARC).
    class Sender
      def initialize(inbox)
        @inbox = inbox
        @channel = inbox.channel
      end

      def deliver(to:, subject:, html_body:, text_body: nil, from_email: nil, reply_to: nil, headers: nil)
        mail = build_mail(to: to, subject: subject, html_body: html_body, text_body: text_body,
                          from_email: from_email, reply_to: reply_to, headers: headers)
        @channel.microsoft? ? deliver_via_graph(mail) : deliver_via_smtp(mail)
        mail.message_id
      end

      private

      def from_address(from_email)
        from_email.presence || @channel.email
      end

      def build_mail(to:, subject:, html_body:, text_body:, from_email:, reply_to:, headers:)
        addr = from_address(from_email)
        mail = Mail.new
        mail.to = to
        mail.from = addr
        mail.subject = subject
        mail.reply_to = reply_to if reply_to.present?
        mail.message_id = "<campaign-#{SecureRandom.hex(12)}@#{addr.split('@').last}>"
        (headers || {}).each { |key, value| mail[key] = value }
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body html_body
        end
        if text_body.present?
          mail.text_part = Mail::Part.new do
            content_type 'text/plain; charset=UTF-8'
            body text_body
          end
        end
        mail
      end

      def deliver_via_graph(mail)
        token = ::Microsoft::GraphTokenService.new(channel: @channel).access_token
        uri = URI('https://graph.microsoft.com/v1.0/me/sendMail')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 30
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Content-Type'] = 'text/plain'
        request.body = Base64.strict_encode64(mail.to_s)
        response = http.request(request)
        return if response.code.to_i == 202

        raise StandardError, "graph_send_failed (#{response.code})"
      end

      def deliver_via_smtp(mail)
        mail.delivery_method(:smtp, smtp_settings)
        mail.deliver
      end

      def smtp_settings
        if @channel.google?
          token = ::Google::RefreshOauthTokenService.new(channel: @channel).access_token
          { address: 'smtp.gmail.com', port: 587, user_name: @channel.imap_login, password: token,
            authentication: 'xoauth2', enable_starttls_auto: true, open_timeout: 15, read_timeout: 30 }
        else
          { address: @channel.smtp_address, port: @channel.smtp_port, user_name: @channel.smtp_login,
            password: @channel.smtp_password, authentication: @channel.smtp_authentication.presence || 'plain',
            enable_starttls_auto: @channel.smtp_enable_starttls_auto, open_timeout: 15, read_timeout: 30 }
        end
      end
    end
  end
end
