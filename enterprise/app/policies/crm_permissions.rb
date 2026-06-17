# Shared helper for CRM Pundit policies (EE overlay).
#
# LOCKED PRODUCT DECISION: "if the admin granted it, the user has it".
# - Administrators keep full CRM access.
# - Plain agents (account_user present, NO custom_role) keep full CRM access too
#   (granularity only applies to custom-role seats, preserving pre-PR14 behavior).
# - Custom-role users are gated by the granular crm_* keys (crm_admin implies all).
module CrmPermissions
  def crm_permission?(key)
    return false if account_user.blank?
    return true if account_user.administrator?

    custom_role = account_user.custom_role
    # Plain agents (no custom role) retain full CRM access.
    return true if custom_role.blank?

    permissions = custom_role.permissions
    permissions.include?('crm_admin') || permissions.include?(key)
  end
end
