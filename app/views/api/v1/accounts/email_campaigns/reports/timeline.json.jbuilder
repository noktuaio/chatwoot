json.payload do
  json.campaign_id @campaign.id
  json.merge! @timeline
end
