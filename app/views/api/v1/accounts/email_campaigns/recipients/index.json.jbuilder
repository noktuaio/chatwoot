json.payload do
  json.campaign do
    json.partial! 'api/v1/accounts/email_campaigns/campaigns/campaign', campaign: @campaign
  end
  json.recipients do
    json.array! @recipients, partial: 'api/v1/accounts/email_campaigns/recipients/recipient', as: :recipient
  end
  json.meta do
    json.count @recipients_count
    json.current_page @current_page.to_i
  end
  if @result
    json.import_result do
      json.imported @result.imported
      json.duplicates @result.duplicates
      json.invalid @result.invalid
      json.suppressed @result.suppressed
      json.total @result.total
    end
  end
end
