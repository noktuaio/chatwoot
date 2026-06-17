module Autonomia
  module Agents
    module Operate
      # Logging ADITIVO best-effort de eventos de operação (Fase F). NUNCA levanta:
      # qualquer falha é engolida e logada (sem eco de IP/prompt) para jamais quebrar
      # a resposta/handoff. Só é chamado no caminho autonomia (agente nativo).
      class EventLogger
        # IP oculto: NUNCA persistimos o motivo LIVRE do LLM (pode ecoar PII do cliente,
        # conhecimento recuperado ou pedaços de instruction/prompt). Só gravamos um CÓDIGO
        # de uma allowlist fechada; qualquer outra coisa (texto livre, legado, vazio) -> 'other'.
        ALLOWED_REASONS = %w[low_confidence ai_unavailable human_requested missing_knowledge policy other].freeze

        def self.replied(agent:, conversation:, result:)
          create!(
            agent: agent, conversation: conversation, event_type: :replied,
            confidence: result&.confidence,
            answered_from_knowledge: result&.answered_from_knowledge || false
          )
        end

        def self.handed_off(agent:, conversation:, result:)
          create!(
            agent: agent, conversation: conversation, event_type: :handed_off,
            handoff_reason: curated_reason(result)
          )
        end

        def self.create!(agent:, conversation:, **attrs)
          ::Autonomia::Agents::AgentEvent.create!(
            agent: agent, account_id: agent.account_id,
            conversation_id: conversation&.id, **attrs
          )
        rescue StandardError => e
          Rails.logger.warn("[autonomia][events] log_skipped agent=#{agent&.id} #{e.class}")
          nil
        end

        # Motivo do handoff é texto LIVRE do LLM (handoff[:reason]) -> potencial IP/PII.
        # NÃO truncamos e persistimos texto livre: colapsamos para um código da allowlist.
        # Códigos conhecidos da Fase B (low_confidence/ai_unavailable) passam direto; tudo
        # mais (texto livre do LLM, valor desconhecido) vira 'other'. Sem result (erro/
        # timeout) -> nil (agrupado como "outros" no analytics).
        def self.curated_reason(result)
          reason = result&.handoff&.dig(:reason)
          return nil if reason.blank?

          code = reason.to_s.strip.downcase
          ALLOWED_REASONS.include?(code) ? code : 'other'
        end
      end
    end
  end
end
