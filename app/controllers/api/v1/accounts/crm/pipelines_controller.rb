class Api::V1::Accounts::Crm::PipelinesController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]

  def index
    authorize ::Crm::Pipeline
    @pipelines = policy_scope(::Crm::Pipeline).active.order(:position, :id)
    @pipelines_count = @pipelines.count
  end

  def show; end

  def create
    @pipeline = Current.account.crm_pipelines.new(pipeline_params)
    @pipeline.created_by = Current.user
    authorize @pipeline
    @pipeline.save!
    update_goal!
    render :show, status: :created
  end

  def update
    @pipeline.update!(pipeline_params)
    update_goal!
    render :show
  end

  def destroy
    @pipeline.archived!
    render :show
  end

  private

  def fetch_pipeline
    @pipeline = policy_scope(::Crm::Pipeline).find(params[:id])
    authorize @pipeline
  end

  def pipeline_params
    parameter_set(:pipeline).permit(:name, :description, :status, :is_default, :position, metadata: {})
  end

  # Monthly sales target lives in metadata['goals'] and is merged in separately
  # so it never clobbers metadata['ai'] (pipeline AI settings).
  def update_goal!
    goal = params.dig(:pipeline, :goal)
    return if goal.nil?

    metadata = (@pipeline.metadata || {}).deep_dup
    target = goal[:monthly_target_cents].to_i
    if target.positive?
      metadata['goals'] = {
        'monthly_target_cents' => target,
        'currency' => (goal[:currency].presence || 'BRL').to_s.upcase
      }
    else
      metadata.delete('goals')
    end
    @pipeline.update!(metadata: metadata)
  end
end
