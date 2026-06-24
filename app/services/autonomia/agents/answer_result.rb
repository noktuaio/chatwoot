module Autonomia
  module Agents
    # Resultado SÍNCRONO do motor de resposta. Fronteira de segurança: NUNCA carrega
    # instruction/scaffold/prompt montado. `used_knowledge[].content` é conteúdo do próprio
    # usuário (ok expor). `error` é um código curto (ex.: 'ai_unavailable'), nunca a mensagem
    # crua do LLM. `raw_reply` é o texto do modelo antes do portão (gerado, não é IP) — exposto
    # só no Copilot (/suggest); o Testar (/test) o ignora.
    class AnswerResult
      attr_reader :reply, :confidence, :handoff, :used_knowledge,
                  :answered_from_knowledge, :raw_reply, :error

      # handoff: { should: Boolean, reason: String|nil }
      # used_knowledge: Array<{ id:, content:, source: }>
      def initialize(reply:, confidence:, handoff:, used_knowledge: [],
                     answered_from_knowledge: false, raw_reply: nil, error: nil)
        @reply = reply
        @confidence = confidence
        @handoff = handoff
        @used_knowledge = used_knowledge
        @answered_from_knowledge = answered_from_knowledge
        @raw_reply = raw_reply
        @error = error
      end

      # Consumido pelo jbuilder do Testar. NÃO inclui raw_reply (esse é só do Copilot).
      def to_h
        {
          reply: reply,
          confidence: confidence,
          handoff: { should: handoff[:should], reason: handoff[:reason] },
          used_knowledge: used_knowledge,
          answered_from_knowledge: answered_from_knowledge,
          error: error
        }
      end
    end
  end
end
