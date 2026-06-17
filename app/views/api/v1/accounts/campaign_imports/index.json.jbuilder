json.payload do
  json.array! @campaign_imports do |campaign_import|
    json.partial! 'api/v1/models/campaign_import', formats: [:json], resource: campaign_import
  end
end

json.meta do
  json.count @campaign_imports_count
  json.current_page @current_page
end
