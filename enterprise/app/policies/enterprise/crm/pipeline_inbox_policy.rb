module Enterprise::Crm::PipelineInboxPolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_manage_pipelines')
  end

  def show?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id
  end

  def create?
    crm_permission?('crm_manage_pipelines')
  end

  def destroy?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id
  end
end
