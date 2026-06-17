json.payload do
  json.integration_tokens do
    json.array! @integration_tokens, partial: 'integration_token', as: :integration_token
  end
end
