module Autonomia
  module Agents
    # "Copiloto" — sugestão de rascunho ao ATENDENTE humano (não ao cliente final). Reusa o
    # Answerer. Diferença semântica do Testar: SEMPRE devolve um `reply` mesmo sob handoff (o
    # humano revisa). Quando o portão de confiança suprime o `reply` (handoff com fallback nil),
    # cai no `raw_reply` — o melhor esforço do modelo antes do portão (conteúdo gerado, não é IP).
    # NUNCA expõe instruction/scaffold/prompt; o jbuilder /suggest filtra a fronteira de segurança.
    class Copilot
      def initialize(agent:, message:, history: [])
        @agent = agent
        @message = message
        @history = history
      end

      # -> Autonomia::Agents::AnswerResult (com reply garantido p/ o atendente revisar)
      def suggest
        Answerer.new(agent: @agent, query: @message, history: @history).answer
      end
    end
  end
end
