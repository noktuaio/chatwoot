# Shared helper for CRM Pundit policies (EE overlay).
#
# - Administrators keep full CRM access.
# - Plain agents (account_user present, NO custom_role) keep their day-to-day CRM
#   access (cards, reports, AI on cards) but NOT admin-grade configuration. This
#   mirrors the OSS policies, which gate pipelines/stages/automations/inbox
#   settings/integration tokens behind administrator?. Previously plain agents
#   were granted every key, letting any agent alter pipelines/automations and
#   read/issue integration tokens — a privilege escalation.
# - Custom-role users are gated by the granular crm_* keys (crm_admin implies all).
module CrmPermissions
  # Admin-grade keys never granted to a plain (non-custom-role) agent.
  # crm_manage_pipelines covers pipelines, stages, automations, pipeline inboxes
  # and inbox settings; crm_admin covers integration tokens.
  PLAIN_AGENT_DENIED_KEYS = %w[crm_manage_pipelines crm_admin].freeze

  def crm_permission?(key)
    return false if account_user.blank?
    return true if account_user.administrator?

    custom_role = account_user.custom_role
    return PLAIN_AGENT_DENIED_KEYS.exclude?(key) if custom_role.blank?

    permissions = custom_role.permissions
    permissions.include?('crm_admin') || permissions.include?(key)
  end
end
