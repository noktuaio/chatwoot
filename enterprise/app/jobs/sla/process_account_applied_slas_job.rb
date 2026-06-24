class Sla::ProcessAccountAppliedSlasJob < ApplicationJob
  queue_as :medium

  def perform(account)
    # Guarda autoritativa (além do filtro no Trigger): conta sem a feature `sla` não processa SLA.
    return unless account.feature_enabled?('sla')

    account.applied_slas.where(sla_status: %w[active active_with_misses]).find_each do |applied_sla|
      Sla::ProcessAppliedSlaJob.perform_later(applied_sla)
    end
  end
end
