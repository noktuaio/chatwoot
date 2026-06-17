module Enterprise::Crm::ServiceSchedulePolicy
  include CrmPermissions

  # SLA service calendars are CRM account configuration: crm_admin (the highest
  # CRM scope) can manage them without needing the global administrator role.
  def index?
    crm_permission?('crm_admin')
  end

  def create?
    crm_permission?('crm_admin')
  end

  def update?
    crm_permission?('crm_admin') && record.account_id == account.id
  end

  def destroy?
    update?
  end
end
