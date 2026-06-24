class CampaignImportPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator?
  end

  def create?
    administrator?
  end

  def destroy?
    administrator?
  end

  def validate?
    administrator?
  end

  def preview_labels?
    administrator?
  end

  def confirm?
    administrator?
  end

  def errors?
    administrator?
  end

  def report?
    administrator?
  end

  def undo_labels?
    administrator?
  end

  def download?
    administrator?
  end

  private

  def administrator?
    @account_user.administrator?
  end
end
