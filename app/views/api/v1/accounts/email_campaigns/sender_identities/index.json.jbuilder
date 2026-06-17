json.payload do
  json.sender_identities do
    json.array! @sender_identities, partial: 'sender_identity', as: :sender_identity
  end
end
