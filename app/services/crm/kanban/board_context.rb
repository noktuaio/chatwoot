class Crm::Kanban::BoardContext
  attr_reader :params, :account, :user, :account_user

  def initialize(params:, account:, user:, account_user:)
    @params = params
    @account = account
    @user = user
    @account_user = account_user
  end
end
