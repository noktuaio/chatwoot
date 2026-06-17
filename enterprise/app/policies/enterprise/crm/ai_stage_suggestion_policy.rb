module Enterprise::Crm::AiStageSuggestionPolicy
  include CrmPermissions

  def show?
    crm_permission?('crm_view') && card_visible?
  end

  def accept?
    crm_permission?('crm_manage_ai') && card_visible?
  end

  def dismiss?
    crm_permission?('crm_manage_ai') && card_visible?
  end

  def evaluate?
    crm_permission?('crm_manage_ai') && card_visible?
  end
end
