class Crm::InboxSettingPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator? && record.account_id == account.id
  end

  def update?
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

Crm::InboxSettingPolicy.prepend_mod_with('Crm::InboxSettingPolicy')
