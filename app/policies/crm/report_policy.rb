class Crm::ReportPolicy < ApplicationPolicy
  def view?
    account_user.present?
  end
end

Crm::ReportPolicy.prepend_mod_with('Crm::ReportPolicy')
