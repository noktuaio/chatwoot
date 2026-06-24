class Crm::StageAutomationPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator? && record.account_id == account.id
  end

  def create?
    administrator?
  end

  def update?
    show?
  end

  def destroy?
    show?
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

Crm::StageAutomationPolicy.prepend_mod_with('Crm::StageAutomationPolicy')
