class Api::V1::Accounts::SlaPoliciesController < Api::V1::Accounts::EnterpriseAccountsController
  before_action :ensure_sla_feature
  before_action :fetch_sla, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @sla_policies = Current.account.sla_policies
  end

  def show; end

  def create
    @sla_policy = Current.account.sla_policies.create!(permitted_params)
  end

  def update
    @sla_policy.update!(permitted_params)
  end

  def destroy
    ::DeleteObjectJob.perform_later(@sla_policy, Current.user, request.ip) if @sla_policy.present?
    head :ok
  end

  def permitted_params
    params.require(:sla_policy).permit(:name, :description, :first_response_time_threshold, :next_response_time_threshold,
                                       :resolution_time_threshold, :only_during_business_hours, :exclude_groups, :ai_skip_natural_pause,
                                       auto_apply: [:enabled, :event, { inbox_ids: [], pipeline_ids: [] }])
  end

  def fetch_sla
    @sla_policy = Current.account.sla_policies.find_by(id: params[:id])
  end

  # Gate da feature `sla`: a API some (404) quando a conta não tem a feature, alinhado à UI.
  def ensure_sla_feature
    render json: { error: 'sla.disabled' }, status: :not_found unless Current.account.feature_enabled?('sla')
  end
end
