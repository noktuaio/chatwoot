json.payload do
  json.partial! 'api/v1/models/campaign_import', formats: [:json], resource: @campaign_import
end
