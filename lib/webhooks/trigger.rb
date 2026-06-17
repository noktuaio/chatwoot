class Webhooks::Trigger
  SUPPORTED_ERROR_HANDLE_EVENTS = %w[message_created message_updated].freeze
  RETRYABLE_AGENT_BOT_STATUSES = [429, 500].freeze
  # 5xx is retryable for CRM deliveries; 4xx (except none here) is a permanent
  # consumer error and must NOT be retried (plan D5).
  RETRYABLE_CRM_STATUS_RANGE = (500..599).freeze

  class RetryableError < StandardError
    attr_reader :status

    def initialize(status:, message:)
      @status = status
      super(message)
    end
  end

  def initialize(url, payload, webhook_type, secret: nil, delivery_id: nil)
    @url = url
    @payload = payload
    @webhook_type = webhook_type
    @secret = secret
    @delivery_id = delivery_id
  end

  def self.execute(url, payload, webhook_type, secret: nil, delivery_id: nil)
    new(url, payload, webhook_type, secret: secret, delivery_id: delivery_id).execute
  end

  def execute
    perform_request
  rescue StandardError => e
    raise RetryableError.new(status: http_status(e), message: e.message) if retryable_agent_bot_error?(e)
    # CRM deliveries (plan D5/B1): surface transient transport/5xx failures so the
    # dedicated Webhooks::CrmDeliveryJob can retry. Core webhook types still fall
    # through to handle_failure (at-most-once, unchanged).
    raise RetryableError.new(status: http_status(e), message: e.message) if retryable_crm_error?(e)

    handle_failure(e)
  end

  def handle_failure(error)
    handle_error(error)
    Rails.logger.warn "Exception: Invalid webhook URL #{@url} : #{error.message}"
  end

  private

  def perform_request
    body = @payload.to_json
    SafeFetch.fetch(
      @url,
      method: :post,
      body: body,
      headers: request_headers(body),
      open_timeout: webhook_timeout,
      read_timeout: webhook_timeout,
      validate_content_type: false
    ) { |_response| nil }
  end

  def request_headers(body)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    headers['X-Chatwoot-Delivery'] = @delivery_id if @delivery_id.present?
    # Stable per-logical-event id (crm_activities.id) for consumer-side dedup,
    # distinct from the per-attempt X-Chatwoot-Delivery (plan §3.1, R4). Additive.
    headers['X-Chatwoot-Event-Id'] = @payload[:event_id].to_s if @payload.is_a?(Hash) && @payload[:event_id].present?
    if @secret.present?
      ts = Time.now.to_i.to_s
      headers['X-Chatwoot-Timestamp'] = ts
      headers['X-Chatwoot-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, "#{ts}.#{body}")}"
    end
    headers
  end

  def handle_error(error)
    return unless SUPPORTED_ERROR_HANDLE_EVENTS.include?(@payload[:event])
    return unless message

    case @webhook_type
    when :agent_bot_webhook
      update_conversation_status(message)
    when :api_inbox_webhook
      update_message_status(error)
    end
  end

  def update_conversation_status(message)
    conversation = message.conversation
    return unless conversation&.pending?
    return if conversation&.account&.keep_pending_on_bot_failure

    conversation.open!
    create_agent_bot_error_activity(conversation)
  end

  def create_agent_bot_error_activity(conversation)
    content = I18n.t('conversations.activity.agent_bot.error_moved_to_open')
    Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params(conversation, content))
  end

  def activity_message_params(conversation, content)
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
  end

  def update_message_status(error)
    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  end

  def message
    return if message_id.blank?

    if defined?(@message)
      @message
    else
      @message = Message.find_by(id: message_id)
    end
  end

  def message_id
    @payload[:id]
  end

  def webhook_timeout
    raw_timeout = GlobalConfig.get_value('WEBHOOK_TIMEOUT')
    timeout = raw_timeout.presence&.to_i

    timeout&.positive? ? timeout : 5
  end

  def retryable_agent_bot_error?(error)
    @webhook_type == :agent_bot_webhook && RETRYABLE_AGENT_BOT_STATUSES.include?(http_status(error))
  end

  # Retry CRM deliveries on transport failures (timeout/connection -> FetchError)
  # and on 5xx server errors (HttpError). 4xx / SSRF / bad-URL are permanent.
  def retryable_crm_error?(error)
    return false unless @webhook_type == :crm_account_webhook
    return true if error.is_a?(SafeFetch::FetchError)

    RETRYABLE_CRM_STATUS_RANGE.include?(http_status(error).to_i) if error.is_a?(SafeFetch::HttpError)
  end

  def http_status(error)
    return unless error.is_a?(SafeFetch::HttpError)

    error.message.to_s[/\A(\d{3})\b/, 1]&.to_i
  end
end
