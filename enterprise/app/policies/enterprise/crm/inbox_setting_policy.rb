module Enterprise::Crm::InboxSettingPolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_manage_pipelines')
  end

  def show?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id
  end

  def update?
    crm_permission?('crm_manage_pipelines') && record.account_id == account.id
  end
end
