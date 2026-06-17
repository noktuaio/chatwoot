json.id integration_token.id
json.name integration_token.name
json.status integration_token.status
json.scopes integration_token.granted_scopes
json.account_id integration_token.account_id
json.last_used_at integration_token.last_used_at
json.created_at integration_token.created_at
json.updated_at integration_token.updated_at
if integration_token.created_by
  json.created_by do
    json.id integration_token.created_by.id
    json.name integration_token.created_by.name
  end
end
