class Crm::FollowUpPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    visible_card_scope.exists?(id: record.card_id)
  end

  def create?
    account_user.present?
  end

  def update?
    show?
  end

  def destroy?
    update?
  end

  def complete?
    update?
  end

  def cancel?
    update?
  end

  def reschedule?
    update?
  end

  def dismiss_reminder?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      visible_card_ids = Pundit.policy_scope!(user_context, Crm::Card).select(:id)
      scope.where(account_id: account.id, card_id: visible_card_ids)
    end
  end

  private

  def visible_card_scope
    Pundit.policy_scope!(user_context, Crm::Card)
  end
end

Crm::FollowUpPolicy.prepend_mod_with('Crm::FollowUpPolicy')
