json.payload do
  json.array! @whatsapp_api_message_templates do |template|
    json.partial! 'api/v1/models/whatsapp_api_message_template', formats: [:json], resource: template
  end
end
