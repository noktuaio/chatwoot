module Enterprise::Crm::ServiceSchedulePolicy
  # SLA service calendars são CONFIGURAÇÃO da conta (como as SLA policies, que são admin-only) e
  # afetam o cálculo do SLA. Portanto exigem nível ADMIN-GRADE: administrador OU custom role com
  # `crm_admin`. NÃO usamos `CrmPermissions#crm_permission?` aqui porque ele concede acesso pleno ao
  # AGENTE COMUM (sem custom role) — adequado para cards/kanban, mas perigoso para config de SLA.
  def index?
    service_schedule_admin?
  end

  def create?
    service_schedule_admin?
  end

  def update?
    service_schedule_admin? && record.account_id == account.id
  end

  def destroy?
    update?
  end

  private

  def service_schedule_admin?
    return false if account_user.blank?
    return true if account_user.administrator?

    custom_role = account_user.custom_role
    custom_role.present? && custom_role.permissions.include?('crm_admin')
  end
end
