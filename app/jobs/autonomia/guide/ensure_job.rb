module Autonomia
  module Guide
    class EnsureJob < ApplicationJob
      queue_as :medium

      def perform(account_id)
        account = ::Account.find_by(id: account_id)
        return if account.blank?

        agent = ::Autonomia::Guide::Seed.ensure_for(account)
        if agent.present?
          Rails.logger.info("[autonomia][guide][ensure_job] account=#{account.id} agent=#{agent.id} ready=true")
        else
          Rails.logger.warn("[autonomia][guide][ensure_job] account=#{account.id} ready=false")
        end
      end
    end
  end
end
