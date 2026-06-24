# Guia da Plataforma — endpoint READ-ONLY de onboarding/suporte. NÃO admin-only (qualquer perfil da
# conta usa). Gated pela elegibilidade Autonomia (ENV master + chave de IA do Kanban por conta) — o
# mesmo gate que faz o Guia nascer sozinho. Nunca opera/escreve: só responde, orienta e sugere a tela.
class Api::V1::Accounts::Autonomia::GuideController < Api::V1::Accounts::BaseController
  before_action :ensure_guide_enabled

  def chat
    result = ::Autonomia::Guide::Chat.new(
      account: Current.account,
      user: Current.user,
      message: params[:message],
      history: history_param,
      route_context: params[:route_context]
    ).perform

    render json: {
      text: result.text,
      navigation: result.navigation,
      grounded: result.grounded,
      confidence: result.confidence,
      available: result.available,
      escalate: result.escalate
    }
  end

  private

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end

  # Robusto: aceita só itens hash/params (string/símbolo); um item malformado (ex.: "x") não derruba
  # o endpoint com TypeError antes do rescue do serviço.
  def history_param
    Array(params[:history]).filter_map do |h|
      next unless h.is_a?(Hash) || h.is_a?(ActionController::Parameters)

      { role: h[:role].to_s, content: h[:content].to_s }
    end
  end
end
