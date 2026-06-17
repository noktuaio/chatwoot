class Crm::FollowUps::MetadataSanitizer
  ALLOWED_KEYS = %w[
    message_body
    whatsapp_api_message_template_id
    template_name
    template_namespace
    template_language
    template_processed_params
    sent_message_id
    sent_at
    send_mode
    send_error
    source
    touch
  ].freeze

  def initialize(metadata:, automation_mode:)
    @metadata = (metadata || {}).to_h.stringify_keys
    @automation_mode = automation_mode
  end

  def perform
    return {} unless @automation_mode.to_s == 'auto_send_message'

    sanitized = @metadata.slice(*ALLOWED_KEYS)
    sanitized['whatsapp_api_message_template_id'] = sanitized['whatsapp_api_message_template_id'].presence&.to_i
    sanitized['template_processed_params'] = sanitized['template_processed_params'].to_h if sanitized.key?('template_processed_params')
    sanitized.compact
  end
end
