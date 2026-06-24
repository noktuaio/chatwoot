class Crm::ServiceSchedulePolicy < ApplicationPolicy
  # SLA service calendars are account configuration: administrators only.
  # The EE overlay (Enterprise::Crm::ServiceSchedulePolicy) relaxes this to crm_admin.
  def index?
    administrator?
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

Crm::ServiceSchedulePolicy.prepend_mod_with('Crm::ServiceSchedulePolicy')
