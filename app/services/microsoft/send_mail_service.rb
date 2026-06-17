require 'ostruct'

# Envia e-mail pela Microsoft Graph API em formato MIME.
# Isso ignora o SMTP AUTH (que o Security Defaults bloqueia tenant-wide) e funciona
# mesmo com Security Defaults ligado. O MIME permite In-Reply-To/References (threading).
# Ref: https://learn.microsoft.com/en-us/graph/api/user-sendmail
class Microsoft::SendMailService
  pattr_initialize [:channel!, :message!, :to_emails!, :cc_emails, :bcc_emails, :subject!, :html_body!, :text_body, :in_reply_to, :references]

  GRAPH_API_BASE = 'https://graph.microsoft.com/v1.0'.freeze
  MAX_ATTACHMENT_SIZE = 20.megabytes

  def perform
    response = send_mail_via_graph_api
    handle_response(response)
  end

  private

  def send_mail_via_graph_api
    uri = URI("#{GRAPH_API_BASE}/me/sendMail")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'text/plain' # MIME format requires text/plain
    request.body = Base64.strict_encode64(build_mime_message)

    http.request(request)
  end

  def access_token
    graph_token_service.access_token
  end

  def graph_token_service
    @graph_token_service ||= Microsoft::GraphTokenService.new(channel: channel)
  end

  def build_mime_message
    mail = Mail.new
    apply_mail_headers(mail)
    apply_threading_headers(mail)
    partition_attachments
    apply_mail_body(mail)
    apply_attachments(mail)
    mail.to_s
  end

  # Igual ao SMTP: até o teto vira anexo; o excedente vira LINK no corpo
  # (em vez de sumir silenciosamente).
  def partition_attachments
    @inline_attachments = []
    @overflow_attachments = []
    return if message.attachments.blank?

    total_size = 0
    message.attachments.each do |attachment|
      blob = attachment.file.blob
      next if blob.blank?

      if total_size + blob.byte_size <= MAX_ATTACHMENT_SIZE
        total_size += blob.byte_size
        @inline_attachments << attachment
      else
        @overflow_attachments << attachment
      end
    end
  end

  def apply_mail_headers(mail)
    mail.to = Array(to_emails).compact
    mail.from = channel.email
    mail.subject = subject
    mail.message_id = generate_message_id
    mail.cc = Array(cc_emails).compact if cc_emails.present?
    mail.bcc = Array(bcc_emails).compact if bcc_emails.present?
  end

  # A Graph API bloqueia In-Reply-To/References via internetMessageHeaders, mas o MIME permite.
  def apply_threading_headers(mail)
    return if in_reply_to.blank?

    mail.in_reply_to = ensure_angle_brackets(in_reply_to)
    mail.references = ensure_angle_brackets(references || in_reply_to)
  end

  def apply_mail_body(mail)
    html_content = html_body_with_overflow_links
    text_content = text_body

    mail.html_part = Mail::Part.new do
      content_type 'text/html; charset=UTF-8'
      body html_content
    end

    return if text_content.blank?

    mail.text_part = Mail::Part.new do
      content_type 'text/plain; charset=UTF-8'
      body text_content
    end
  end

  def html_body_with_overflow_links
    return html_body if @overflow_attachments.blank?

    links = @overflow_attachments.map do |attachment|
      "<p><a href=\"#{attachment.file_url}\" target=\"_blank\">#{attachment.file.filename}</a></p>"
    end.join
    "#{html_body}#{links}"
  end

  def apply_attachments(mail)
    @inline_attachments.each do |attachment|
      attachment.file.blob.open do |file|
        mail.add_file filename: attachment.file.filename.to_s, content: file.read
      end
    end
  end

  def ensure_angle_brackets(value)
    return nil if value.blank?

    value = value.to_s.strip
    return value if value.start_with?('<') && value.end_with?('>')

    "<#{value.gsub(/^<|>$/, '')}>"
  end

  def handle_response(response)
    case response.code.to_i
    when 202
      Rails.logger.info("Microsoft Graph API: Email sent successfully via MIME for message #{message.id}")
      OpenStruct.new(success: true, message_id: generate_message_id)
    when 401
      raise_auth_error('Authentication failed - token may be expired or invalid')
    when 403
      raise_auth_error('Permission denied - Mail.Send scope may be missing')
    else
      error_message = begin
        JSON.parse(response.body).dig('error', 'message')
      rescue JSON::ParserError, TypeError
        nil
      end
      # Detalhe do provedor só no log; ao status de falha vai um código estável.
      Rails.logger.error("Microsoft Graph API error (#{response.code}): #{error_message}")
      raise StandardError, "microsoft_graph_send_failed (#{response.code})"
    end
  end

  def raise_auth_error(msg)
    Rails.logger.error("Microsoft Graph API: #{msg}")
    raise StandardError, msg
  end

  # Message ID único que o Chatwoot reconhece para threading.
  def generate_message_id
    conversation = message.conversation
    "<conversation/#{conversation.uuid}/messages/#{message.id}@#{email_domain}>"
  end

  def email_domain
    channel.email.split('@').last
  end
end
