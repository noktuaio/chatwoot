module Crm
  module Ai
    class DefaultStageCriteria
      TEMPLATES = {
        'novo' => 'Primeiro contato ou lead recém-criado. Cliente demonstrou interesse inicial, fez primeira pergunta ou respondeu pela primeira vez. Ainda não há diagnóstico de necessidade nem proposta enviada.',
        'em atendimento' => 'Conversa ativa com qualificação em andamento: agente ou IA está entendendo necessidade, coletando dados, tirando dúvidas ou agendando. Ainda não houve envio formal de proposta, orçamento ou condições comerciais.',
        'proposta' => 'Proposta, orçamento, plano ou condições comerciais já foram apresentados. Cliente está avaliando, negociando valores, prazos ou comparando opções. Ainda não confirmou fechamento nem recusa definitiva.',
        'fechamento' => 'Cliente confirmou intenção de compra, aceitou proposta, solicitou link de pagamento, assinatura ou próximo passo operacional de contratação. Conversa indica conversão iminente ou concluída.',
        'perdido' => 'Lead encerrado sem conversão: cliente recusou explicitamente, pediu para não ser contatado, informou que fechou com concorrente, número inválido ou sem resposta após tentativas definidas pelo funil, ou conversa foi encerrada pelo agente como perdida. Não usar para leads ainda em negociação ativa ou que apenas disseram "vou pensar".'
      }.freeze

      def self.criteria_for(stage_name)
        key = stage_name.to_s.strip.downcase
        TEMPLATES[key] || TEMPLATES[key.gsub(/\s+/, ' ')]
      end

      def self.metadata_for(stage_name)
        criteria = criteria_for(stage_name)
        return {} if criteria.blank?

        { 'ai_criteria' => criteria }
      end
    end
  end
end
