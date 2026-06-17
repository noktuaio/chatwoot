module Crm
  module Ai
    class Observer
      def initialize(card:)
        @card = card
      end

      def schedule_evaluation
        return unless Config.enabled?

        token = schedule_token
        Crm::Ai::EvaluateCardJob.set(wait: Config::DEBOUNCE_SECONDS.seconds).perform_later(@card.id, token)
      end

      private

      def schedule_token
        token = Time.current.to_f
        metadata = (@card.metadata || {}).deep_dup
        metadata['ai'] = (metadata['ai'] || {}).merge(
          'evaluate_after' => (Time.current + Config::DEBOUNCE_SECONDS.seconds).iso8601,
          'evaluate_token' => token
        )
        @card.update!(metadata: metadata)
        token
      end
    end
  end
end
