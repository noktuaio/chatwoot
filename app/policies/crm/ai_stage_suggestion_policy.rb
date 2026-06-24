class Crm::AiStageSuggestionPolicy < ApplicationPolicy
  def show?
    card_visible?
  end

  def accept?
    card_visible?
  end

  def dismiss?
    card_visible?
  end

  def evaluate?
    card_visible?
  end

  private

  def card_visible?
    Pundit.policy!(user_context, record.card).show?
  end
end

Crm::AiStageSuggestionPolicy.prepend_mod_with('Crm::AiStageSuggestionPolicy')
