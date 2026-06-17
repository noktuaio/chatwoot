class Crm::PipelinePolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    account_user.present? && record.account_id == account.id
  end

  def create?
    administrator?
  end

  def update?
    administrator? && record.account_id == account.id
  end

  def destroy?
    update?
  end

  def manage_ai?
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

Crm::PipelinePolicy.prepend_mod_with('Crm::PipelinePolicy')
