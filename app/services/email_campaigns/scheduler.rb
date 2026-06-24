module EmailCampaigns
  # Picks up due scheduled campaigns, transitions them to sending under a lock, and enqueues
  # delivery. Guarded by Config.enabled?; defensive per-campaign so one failure never strands
  # the batch.
  class Scheduler
    def perform
      return unless Config.enabled?

      EmailCampaign.due.find_each(batch_size: 50) { |campaign| start(campaign) }
    end

    private

    def start(campaign)
      enqueue = false
      campaign.with_lock do
        campaign.reload
        next unless campaign.scheduled? && campaign.scheduled_at <= Time.current
        # Aceita os dois modos: SES (sender_identity verificado) e direto (caixa conectada).
        next unless campaign.sender_ready?

        campaign.mark_sending!
        enqueue = true
      end
      EmailCampaigns::DeliveryJob.perform_later(campaign.id) if enqueue && Config.enabled?
    rescue StandardError => e
      campaign&.update(status: :failed, last_error: e.message.to_s.truncate(500))
    end
  end
end
