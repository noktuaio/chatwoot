class Crm::Cards::CreateAuthorizer
  def initialize(account:, user:, account_user:)
    @account = account
    @user = user
    @account_user = account_user
  end

  def authorize!(attributes, conversation:)
    return if administrator? || conversation.present?

    authorize_owner!(attributes)
    authorize_team!(attributes)
  end

  private

  def authorize_owner!(attributes)
    return if attributes[:owner_id].blank?
    return if attributes[:owner_id].to_i == @user.id

    raise Pundit::NotAuthorizedError
  end

  def authorize_team!(attributes)
    return if attributes[:team_id].blank?
    return if @user.teams.where(account_id: @account.id).exists?(id: attributes[:team_id])

    raise Pundit::NotAuthorizedError
  end

  def administrator?
    @account_user&.administrator?
  end
end
