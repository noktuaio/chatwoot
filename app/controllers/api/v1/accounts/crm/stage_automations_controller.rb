class Api::V1::Accounts::Crm::StageAutomationsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_stage, only: [:index, :create]
  before_action :fetch_stage_automation, only: [:show, :update, :destroy]

  def index
    authorize ::Crm::StageAutomation
    @stage_automations = policy_scope(::Crm::StageAutomation)
                         .where(stage_id: @stage.id)
                         .includes(:steps)
                         .ordered
    @stage_automations_count = @stage_automations.count
  end

  def show; end

  def create
    authorize ::Crm::StageAutomation
    @stage_automation = Crm::StageAutomations::Persister.new(
      account: Current.account,
      user: Current.user,
      stage: @stage,
      attributes: stage_automation_params
    ).create!
    render :show, status: :created
  end

  def update
    @stage_automation = Crm::StageAutomations::Persister.new(
      account: Current.account,
      user: Current.user,
      stage: @stage_automation.stage,
      attributes: stage_automation_params
    ).update!(@stage_automation)
    render :show
  end

  def destroy
    @stage_automation.destroy!
    head :no_content
  end

  private

  def fetch_stage
    @stage = policy_scope(::Crm::PipelineStage).find(params[:stage_id])
  end

  def fetch_stage_automation
    @stage_automation = policy_scope(::Crm::StageAutomation).includes(:steps).find(params[:id])
    authorize @stage_automation
  end

  def stage_automation_params
    parameter_set(:stage_automation).permit(
      :name, :description, :trigger_event, :enabled, :position,
      metadata: {},
      steps: [:position, :delay_seconds, :action_type, { action_config: {} }]
    ).to_h.with_indifferent_access
  end
end
