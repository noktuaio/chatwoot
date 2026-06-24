module Enterprise::Crm::ReportPolicy
  include CrmPermissions

  def view?
    crm_permission?('crm_view_reports')
  end
end
