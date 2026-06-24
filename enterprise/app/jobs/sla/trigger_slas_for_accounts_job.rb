class Sla::TriggerSlasForAccountsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.joins(:sla_policies).distinct.find_each do |account|
      # Só processa SLA de contas com a feature `sla` ligada (mesmo gate do Crm::SlaAutoApplyJob);
      # uma conta com SLA policy mas feature off não deve ser processada.
      next unless account.feature_enabled?('sla')

      Rails.logger.info "Enqueuing ProcessAccountAppliedSlasJob for account #{account.id}"
      Sla::ProcessAccountAppliedSlasJob.perform_later(account)
    end
  end
end
