class Crm::PipelineInboxPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator? && record.account_id == account.id
  end

  def create?
    administrator?
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

Crm::PipelineInboxPolicy.prepend_mod_with('Crm::PipelineInboxPolicy')
