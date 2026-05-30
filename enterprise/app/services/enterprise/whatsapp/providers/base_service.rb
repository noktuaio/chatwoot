module Enterprise::Whatsapp::Providers::BaseService
  attr_reader :last_error

  def process_response(response, message)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      @last_error = nil
      parsed_response['messages'].first['id']
    else
      handle_error(response, message)
      nil
    end
  end

  def handle_error(response, message)
    Rails.logger.error response.body
    @last_error = parsed_error(response)
    return if message.blank?

    error_message = @last_error[:message]
    return if error_message.blank?

    message.external_error = error_message
    message.status = :failed
    message.save!
  end

  def parsed_error(response)
    parsed_response = response.parsed_response
    error = parsed_response.is_a?(Hash) ? parsed_response['error'] || {} : {}
    {
      code: error['code'],
      title: error['title'],
      message: error['error_user_msg'] || error['message']
    }
  end
end
