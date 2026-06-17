json.payload do
  json.partial! 'api/v1/models/whatsapp_api_campaign', formats: [:json], resource: @whatsapp_api_campaign
end
