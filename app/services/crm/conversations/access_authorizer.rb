class Crm::Conversations::AccessAuthorizer
  def initialize(account:, user:, account_user:)
    @account = account
    @user = user
    @account_user = account_user
  end

  def authorize!(conversation)
    return if visibility.visible?(conversation)

    raise Pundit::NotAuthorizedError
  end

  private

  def visibility
    @visibility ||= Crm::Conversations::Visibility.new(account: @account, user: @user, account_user: @account_user)
  end
end
