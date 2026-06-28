class Crm::Ai::ExchangeRateRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Crm::Ai::ExchangeRate.refresh!
  end
end
