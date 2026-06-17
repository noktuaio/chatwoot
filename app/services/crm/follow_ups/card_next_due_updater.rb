class Crm::FollowUps::CardNextDueUpdater
  def self.update(card)
    new(card).perform
  end

  def initialize(card)
    @card = card
  end

  def perform
    @card.update!(next_follow_up_at: next_due_at)
  end

  private

  def next_due_at
    @card.follow_ups.active.order(:due_at).limit(1).pick(:due_at)
  end
end
