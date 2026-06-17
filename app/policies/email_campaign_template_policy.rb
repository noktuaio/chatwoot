class EmailCampaignTemplatePolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    # Own-account templates and shared GLOBAL templates (account_id IS NULL) are both viewable.
    administrator? && (record.account_id.nil? || record.account_id == account.id)
  end

  def create?
    administrator?
  end

  def destroy?
    # Global templates are read-only; only own-account templates can be deleted.
    administrator? && record.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: [account.id, nil])
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
