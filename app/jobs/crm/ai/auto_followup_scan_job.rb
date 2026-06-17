class Crm::Ai::AutoFollowupScanJob < ApplicationJob
  queue_as :scheduled_jobs

  # Cron entry (mirrors StaleCardsJob). Iterates active pipelines, and for each
  # pipeline whose auto_followup config is enabled, runs the planner to detect
  # newly-stalled cards and create touch #1 of the cadence.
  #
  # Flags are checked INSIDE the job (existing pattern): the global CRM AI flag
  # short-circuits everything, then each pipeline short-circuits on its own
  # auto_followup.enabled toggle.
  def perform
    return unless Crm::Ai::Config.enabled?

    Crm::Pipeline.active.find_each do |pipeline|
      cfg = Crm::Ai::Config.auto_followup_settings(pipeline)
      next unless cfg[:enabled]

      Crm::FollowUps::AutoFollowupPlanner.new(pipeline: pipeline).perform
    end
  end
end
