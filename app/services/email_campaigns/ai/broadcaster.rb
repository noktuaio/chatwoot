module EmailCampaigns
  module Ai
    # Empurra via ActionCable o resultado da geração de e-mail para os admins da conta (quem usa o
    # builder) — o FE mostra um toast + atualiza o selo da campanha na lista em tempo real.
    class Broadcaster
      include Events::Types

      def self.ready(campaign)
        new(campaign).broadcast(EMAIL_CAMPAIGN_AI_READY)
      end

      def self.failed(campaign)
        new(campaign).broadcast(EMAIL_CAMPAIGN_AI_FAILED)
      end

      def initialize(campaign)
        @campaign = campaign
      end

      def broadcast(event)
        tokens = @campaign.account.administrators.filter_map(&:pubsub_token)
        return if tokens.empty?

        ActionCableBroadcastJob.perform_later(tokens, event, payload)
      end

      private

      def payload
        {
          campaign_id: @campaign.id,
          name: @campaign.name,
          ai_status: @campaign.ai_status,
          ai_error: @campaign.ai_error,
          account_id: @campaign.account_id
        }
      end
    end
  end
end
