module Enterprise::Crm::IntegrationTokenPolicy
  include CrmPermissions

  # Minting and revoking CRM integration tokens is gated on crm_admin (the highest
  # CRM scope). crm_admin holders can manage the full credential lifecycle without
  # needing the global administrator role.
  def index?
    crm_permission?('crm_admin')
  end

  def create?
    crm_permission?('crm_admin')
  end

  def destroy?
    crm_permission?('crm_admin')
  end

  def rotate?
    crm_permission?('crm_admin')
  end
end
