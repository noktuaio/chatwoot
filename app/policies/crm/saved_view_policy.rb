class Crm::SavedViewPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    scope.exists?(id: record.id)
  end

  def create?
    account_user.present?
  end

  # Only the owner (or an administrator) may mutate a saved view; everyone else
  # gets read-only access through the visibility scope.
  def update?
    record.owned_by?(user) || administrator?
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id).visible_to(user&.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end

Crm::SavedViewPolicy.prepend_mod_with('Crm::SavedViewPolicy')
