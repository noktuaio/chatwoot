conversation_visibility = Crm::Conversations::Visibility.new(
  account: Current.account,
  user: Current.user,
  account_user: Current.account_user
)

json.payload do
  json.partial!(
    'api/v1/accounts/crm/follow_ups/follow_up',
    follow_up: @follow_up,
    conversation_visibility: conversation_visibility
  )
end
