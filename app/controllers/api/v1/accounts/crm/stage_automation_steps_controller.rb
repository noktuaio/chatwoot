class Api::V1::Accounts::Crm::StageAutomationStepsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_stage_automation
  before_action :fetch_step, only: [:update, :destroy]

  def create
    authorize ::Crm::StageAutomationStep
    @step = @stage_automation.steps.create!(
      account: Current.account,
      position: step_params[:position] || next_position,
      delay_seconds: step_params[:delay_seconds] || 0,
      action_type: step_params[:action_type],
      action_config: step_params[:action_config] || {}
    )
    render :show, status: :created
  end

  def update
    @step.update!(step_params)
    render :show
  end

  def destroy
    @step.destroy!
    head :no_content
  end

  private

  def fetch_stage_automation
    @stage_automation = policy_scope(::Crm::StageAutomation).find(params[:stage_automation_id])
    authorize @stage_automation, :show?
  end

  def fetch_step
    @step = policy_scope(::Crm::StageAutomationStep).where(stage_automation: @stage_automation).find(params[:id])
    authorize @step
  end

  def step_params
    parameter_set(:step).permit(:position, :delay_seconds, :action_type, action_config: {}).to_h.with_indifferent_access
  end

  def next_position
    (@stage_automation.steps.maximum(:position) || -1) + 1
  end
end
