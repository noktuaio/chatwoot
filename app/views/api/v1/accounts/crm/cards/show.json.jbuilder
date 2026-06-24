json.payload do
  json.merge! Crm::Cards::DetailPayloadBuilder.new(
    card: @card,
    user: Current.user,
    account_user: Current.account_user
  ).perform
end
