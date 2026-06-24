class Crm::AgentBookingProfilePolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def create?
    administrator?
  end

  def show?
    administrator? && record.account_id == account.id
  end

  def update?
    administrator? && record.account_id == account.id
  end

  def destroy?
    administrator? && record.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
