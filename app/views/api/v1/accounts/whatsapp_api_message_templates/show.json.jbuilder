json.payload do
  json.partial! 'api/v1/models/whatsapp_api_message_template', formats: [:json], resource: @whatsapp_api_message_template
end
