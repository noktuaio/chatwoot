class Crm::Ai::EnrichCardMediaJob < ApplicationJob
  queue_as :low

  def perform(card_id)
    return unless Crm::Ai::Config.media_enabled?

    card = Crm::Card.find_by(id: card_id)
    return if card.blank?

    Crm::Ai::MediaEnricher.new(card: card).perform
  end
end
