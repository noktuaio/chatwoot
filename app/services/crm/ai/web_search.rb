module Crm
  module Ai
    # Kill-switch ÚNICO da busca web nativa da Responses API (tool {type:"web_search"}).
    # Os 4 call sites (Construtor, Revisor, Answerer, Campanhas) chamam WebSearch.tools e
    # passam o resultado em ResponsesClient#create(tools:)/create_background(tools:).
    # Habilitado por ENV AI_WEB_SEARCH_ENABLED (default TRUE) — desliga em produção sem
    # redeploy se custo/latência/comportamento ruim. nil quando desabilitado ⇒ base_body
    # não inclui :tools ⇒ corpo idêntico ao legado (zero regressão).
    module WebSearch
      TOOL = [{ type: 'web_search' }].freeze

      def self.tools
        enabled? ? TOOL : nil
      end

      def self.enabled?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch('AI_WEB_SEARCH_ENABLED', true))
      end
    end
  end
end
