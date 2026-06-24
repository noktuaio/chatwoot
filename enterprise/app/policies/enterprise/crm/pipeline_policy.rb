module Enterprise::Crm::PipelinePolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_view')
  end

  def show?
    crm_permission?('crm_view') && record.account_id == account.id
  end

  def create?
    crm_permission?('crm_manage_pipelines')
  end

  def update?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id
  end

  def destroy?
    update?
  end

  def manage_ai?
    crm_permission?('crm_manage_ai') && record.account_id == account.id
  end
end
