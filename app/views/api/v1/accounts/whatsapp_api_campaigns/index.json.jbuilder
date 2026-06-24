json.payload do
  json.array! @whatsapp_api_campaigns do |campaign|
    json.partial! 'api/v1/models/whatsapp_api_campaign', formats: [:json], resource: campaign
  end
end

json.meta do
  json.count @whatsapp_api_campaigns_count
  json.current_page @current_page
end
