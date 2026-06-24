class Crm::StageAutomationStepPolicy < ApplicationPolicy
  def create?
    administrator?
  end

  def update?
    administrator? && record.account_id == account.id
  end

  def destroy?
    update?
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

Crm::StageAutomationStepPolicy.prepend_mod_with('Crm::StageAutomationStepPolicy')
