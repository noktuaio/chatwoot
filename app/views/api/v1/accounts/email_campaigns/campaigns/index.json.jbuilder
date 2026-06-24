json.payload do
  json.campaigns do
    json.array! @campaigns, partial: 'campaign', as: :campaign
  end
end
