class Crm::Ai::StaleCardsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless Crm::Ai::Config.enabled?

    Crm::Pipeline.active.find_each do |pipeline|
      settings = Crm::Ai::Config.pipeline_ai_settings(pipeline)
      next if settings[:enabled] == false

      stale_hours = settings[:stale_hours].presence || Crm::Ai::Config::DEFAULT_STALE_HOURS
      cutoff = stale_hours.to_i.hours.ago

      pipeline.cards.open.where('last_activity_at < ?', cutoff).find_each do |card|
        Crm::Ai::EvaluateCardJob.perform_later(card.id)
      end
    end
  end
end
