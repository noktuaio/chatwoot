conversation_visibility = local_assigns[:conversation_visibility] || Crm::Conversations::Visibility.new(
  account: Current.account,
  user: Current.user,
  account_user: Current.account_user
)

json.merge! Crm::Cards::PayloadBuilder.new(
  card,
  user: Current.user,
  account_user: Current.account_user,
  conversation_visibility: conversation_visibility
).perform
