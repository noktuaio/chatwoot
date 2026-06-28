module Crm
  module Ai
    # Tabela de preço por modelo p/ ESTIMAR custo (USD por 1M tokens).
    #
    # ATENÇÃO: os valores DEFAULT são PLACEHOLDER (zero) — precisam ser AJUSTADOS para o
    # preço real dos modelos contratados antes que o dashboard mostre custo significativo.
    # Override sem deploy via ENV (1M tokens, "input,cached,output"):
    #   CRM_AI_PRICE_GPT_5_4="2.5,0.25,10"
    #   CRM_AI_PRICE_GPT_5_4_MINI="0.15,0.015,0.6"
    # A chave da ENV é o modelo em UPPER, com tudo que não for [A-Z0-9] virando "_".
    module Pricing
      ZERO_RATE = { input: 0.0, cached: 0.0, output: 0.0 }.freeze

      # USD / 1M tokens. AJUSTAR com o preço real (cached = input cacheado, desconto OpenAI).
      DEFAULT_RATES = {
        'gpt-5.4' => { input: 0.0, cached: 0.0, output: 0.0 },      # AJUSTAR
        'gpt-5.4-mini' => { input: 0.0, cached: 0.0, output: 0.0 }  # AJUSTAR
      }.freeze

      def self.rate(model)
        env = ENV["CRM_AI_PRICE_#{model.to_s.upcase.gsub(/[^A-Z0-9]/, '_')}"]
        if env.present?
          input, cached, output = env.split(',').map { |v| v.to_s.strip.to_f }
          return { input: input.to_f, cached: cached.to_f, output: output.to_f }
        end
        DEFAULT_RATES[model.to_s] || ZERO_RATE
      end

      # Custo estimado em USD. input_tokens da Responses API JÁ inclui os cacheados, então o
      # billable não-cacheado = input - cached (cached cobra a tarifa com desconto).
      def self.cost(model:, input_tokens: 0, cached_tokens: 0, output_tokens: 0)
        r = rate(model)
        billable_input = [input_tokens.to_i - cached_tokens.to_i, 0].max
        ((billable_input * r[:input]) + (cached_tokens.to_i * r[:cached]) + (output_tokens.to_i * r[:output])) / 1_000_000.0
      end
    end
  end
end
