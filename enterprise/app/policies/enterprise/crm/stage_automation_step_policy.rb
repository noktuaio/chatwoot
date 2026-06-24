module Enterprise::Crm::StageAutomationStepPolicy
  include CrmPermissions

  def create?
    crm_permission?('crm_manage_pipelines')
  end

  def update?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id
  end

  def destroy?
    update?
  end
end
