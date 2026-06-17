class Api::V1::Accounts::Autonomia::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :ensure_account_administrator

  private

  # Toda a área de Agentes Autonom.ia some (404) quando a flag está desligada — porta única,
  # idêntica ao gate do CRM/EmailCampaigns.
  def ensure_feature_enabled
    head :not_found unless ::Autonomia::Agents::Config.enabled?(Current.account)
  end

  # Só administradores da conta criam/treinam/configuram agentes (construtor é IP e roda jobs de IA).
  # Mesmo padrão usado em endpoints administrativos do core (ex.: oauth_authorization_controller).
  def ensure_account_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  # Escopos sempre presos à conta corrente (isolamento de conta) — nunca consulta global.
  def agents_scope
    ::Autonomia::Agents::Agent.where(account: Current.account)
  end

  def build_threads_scope
    ::Autonomia::Agents::BuildThread.where(account: Current.account)
  end

  def render_unprocessable(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
