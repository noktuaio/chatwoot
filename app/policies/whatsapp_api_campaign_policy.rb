class WhatsappApiCampaignPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def pause?
    @account_user.administrator?
  end

  def resume?
    @account_user.administrator?
  end

  def cancel?
    @account_user.administrator?
  end
end
