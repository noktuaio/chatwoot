json.payload do
  json.campaign_id @campaign.id
  json.recipients do
    json.array! @recipients do |recipient|
      json.id recipient.id
      json.name recipient.name
      json.email recipient.email
      json.status recipient.status
      json.attempts recipient.attempts
      json.last_event_at recipient.last_event_at
      json.opens @event_counts[:opens][recipient.id].to_i
      json.clicks @event_counts[:clicks][recipient.id].to_i
    end
  end
  json.meta do
    json.count @recipients_count
    json.current_page @current_page
  end
end
