class Api::V1::Accounts::Crm::PipelineInboxesController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_pipeline
  before_action :fetch_pipeline_inbox, only: [:destroy]

  def index
    authorize ::Crm::PipelineInbox
    @pipeline_inboxes = policy_scope(::Crm::PipelineInbox).where(pipeline: @pipeline).includes(:inbox, :default_stage)
    @pipeline_inboxes_count = @pipeline_inboxes.count
  end

  def create
    inbox = Current.account.inboxes.find(pipeline_inbox_params[:inbox_id])
    default_stage = default_stage_for_create
    @pipeline_inbox = Current.account.crm_pipeline_inboxes.new(
      pipeline: @pipeline,
      inbox: inbox,
      default_stage: default_stage,
      auto_create_card: pipeline_inbox_params[:auto_create_card],
      created_by: Current.user
    )
    authorize @pipeline_inbox
    @pipeline_inbox.save!
    render :show, status: :created
  end

  def destroy
    @pipeline_inbox.destroy!
    head :no_content
  end

  private

  def fetch_pipeline
    @pipeline = policy_scope(::Crm::Pipeline).find(params[:pipeline_id])
  end

  def fetch_pipeline_inbox
    @pipeline_inbox = policy_scope(::Crm::PipelineInbox).where(pipeline: @pipeline).find_by!(inbox_id: params[:inbox_id])
    authorize @pipeline_inbox
  end

  def default_stage_for_create
    return if pipeline_inbox_params[:default_stage_id].blank?

    Current.account.crm_pipeline_stages.where(pipeline: @pipeline).find(pipeline_inbox_params[:default_stage_id])
  end

  def pipeline_inbox_params
    parameter_set(:pipeline_inbox).permit(:inbox_id, :default_stage_id, :auto_create_card)
  end
end
