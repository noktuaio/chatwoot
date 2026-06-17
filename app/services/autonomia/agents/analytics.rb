module Autonomia
  module Agents
    # Fase F — Analytics de Desempenho. Agrega autonomia_agent_events SEMPRE escopado
    # por agente+conta sobre uma janela (7d/30d). Nada de IP: só métricas numéricas e
    # motivos de handoff já curados (truncados) pelo EventLogger.
    class Analytics
      RANGES = { '7d' => 7, '30d' => 30 }.freeze
      DEFAULT_RANGE = '7d'.freeze
      TOP_REASONS_LIMIT = 5

      INSIGHT_MIN_EVENTS = 10
      HIGH_HANDOFF_RATE  = 0.4
      LOW_KNOWLEDGE_RATE = 0.3

      def initialize(agent:, range: DEFAULT_RANGE)
        @agent = agent
        @range = RANGES.key?(range.to_s) ? range.to_s : DEFAULT_RANGE
        @days  = RANGES[@range]
        @to    = Time.current
        # Alinha a janela de eventos ao PRIMEIRO balde renderizado pela timeline
        # (que cobre exatamente @days dias terminando hoje). Com @days.days.ago a
        # janela abriria 1 dia antes do primeiro balde -> eventos desse dia entrariam
        # nos cards/rates mas em NENHUMA barra, e a soma das barras < replies_sent.
        @from  = (@days - 1).days.ago.beginning_of_day
      end

      def call
        {
          range: @range,
          conversations_handled: conversations_handled,
          replies_sent: replies_count,
          handoff_count: handoff_count,
          handoff_rate: handoff_rate,
          avg_confidence: avg_confidence,
          knowledge_answer_rate: knowledge_answer_rate,
          top_handoff_reasons: top_handoff_reasons,
          timeline: timeline,
          insight: insight
        }
      end

      private

      def events
        @events ||= ::Autonomia::Agents::AgentEvent
                    .where(autonomia_agent_id: @agent.id, account_id: @agent.account_id)
                    .in_range(@from, @to)
      end

      # group(:event_type) chaveia por NOME do enum ("replied"/"handed_off").
      def counts_by_type
        @counts_by_type ||= events.group(:event_type).count
      end

      def replies_count
        counts_by_type['replied'].to_i
      end

      def handoff_count
        counts_by_type['handed_off'].to_i
      end

      # Conversas distintas tocadas pelo bot na janela (replied OU handed_off).
      def conversations_handled
        events.where.not(conversation_id: nil).distinct.count(:conversation_id)
      end

      # handoffs / (replies + handoffs). 0 quando não houve atividade.
      def handoff_rate
        total = replies_count + handoff_count
        total.zero? ? 0.0 : (handoff_count.to_f / total).round(4)
      end

      def avg_confidence
        avg = events.replied.where.not(confidence: nil).average(:confidence)
        avg ? avg.to_f.round(4) : nil
      end

      # % de replies respondidas a partir do conhecimento.
      def knowledge_answer_rate
        replies = replies_count
        return 0.0 if replies.zero?

        from_knowledge = events.replied.where(answered_from_knowledge: true).count
        (from_knowledge.to_f / replies).round(4)
      end

      # [{ reason:, count: }] dos handoffs com motivo, SEMPRE colapsado a um código da
      # allowlist. Blank/NULL/legado-freeform -> 'other'. Soma no Ruby para que NULL e ''
      # (dado legado) não virem duas linhas distintas e para nunca vazar texto livre legado
      # pelo endpoint (defesa em profundidade, além do EventLogger no caminho de escrita).
      def top_handoff_reasons
        events.handed_off.group(:handoff_reason).count
              .each_with_object(Hash.new(0)) { |(reason, count), acc| acc[curate_reason(reason)] += count }
              .map { |reason, count| { reason: reason, count: count } }
              .sort_by { |row| -row[:count] }
              .first(TOP_REASONS_LIMIT)
      end

      def curate_reason(reason)
        code = reason.to_s.strip.downcase
        ::Autonomia::Agents::Operate::EventLogger::ALLOWED_REASONS.include?(code) ? code : 'other'
      end

      # [{ date: 'YYYY-MM-DD', replies:, handoffs: }] por dia do range (zeros incluídos).
      def timeline
        replied_by_day = day_buckets(events.replied)
        handed_by_day  = day_buckets(events.handed_off)
        (0...@days).map do |offset|
          date = (@to.to_date - (@days - 1 - offset))
          key  = date.iso8601
          { date: key, replies: replied_by_day[key].to_i, handoffs: handed_by_day[key].to_i }
        end
      end

      def day_buckets(scope)
        scope.group('DATE(created_at)').count
             .transform_keys { |d| d.is_a?(String) ? d : d.iso8601 }
      end

      # INSIGHT honesto e simples derivado das métricas. nil quando não há sinal/dados.
      def insight
        return nil if (replies_count + handoff_count) < INSIGHT_MIN_EVENTS

        if handoff_rate >= HIGH_HANDOFF_RATE || knowledge_answer_rate <= LOW_KNOWLEDGE_RATE
          {
            type: handoff_rate >= HIGH_HANDOFF_RATE ? 'high_handoff' : 'low_knowledge',
            handoff_rate: handoff_rate,
            knowledge_answer_rate: knowledge_answer_rate,
            top_reasons: top_handoff_reasons.first(3)
          }
        end
      end
    end
  end
end
