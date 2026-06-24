module Crm
  module Reports
    # Open-card workload by real-time responsible (human assignee/owner, bot, or
    # nobody), reusing Card#responsible_descriptor so the report matches what the
    # board shows. Bounded scan to keep the query predictable.
    class Workload < BaseReport
      MAX_CARDS = 5000

      def perform
        buckets = Hash.new { |hash, key| hash[key] = bucket_template(key) }

        open_cards.find_each(batch_size: 500).with_index do |card, index|
          break if index >= MAX_CARDS

          descriptor = card.responsible_descriptor
          key = bucket_key(descriptor)
          entry = buckets[key]
          entry[:name] ||= descriptor&.dig(:name)
          entry[:count] += 1
        end

        { responsibles: buckets.values.sort_by { |entry| -entry[:count] } }
      end

      private

      def open_cards
        scope = account.crm_cards.where(status: Crm::Card.statuses[:open])
                       .includes(:owner, primary_conversation: :assignee, inbox: { agent_bot_inbox: :agent_bot })
        pipeline.present? ? scope.where(pipeline_id: pipeline.id) : scope
      end

      def bucket_key(descriptor)
        return 'none' if descriptor.blank?

        "#{descriptor[:type]}:#{descriptor[:id]}"
      end

      def bucket_template(key)
        type = key == 'none' ? 'none' : key.split(':').first
        { key: key, type: type, name: nil, count: 0 }
      end
    end
  end
end
