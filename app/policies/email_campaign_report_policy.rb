class EmailCampaignReportPolicy < ApplicationPolicy
  def view?
    administrator?
  end

  def export?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
