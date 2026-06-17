class Api::V1::Accounts::Crm::ServiceSchedulesController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_schedule, only: [:update, :destroy]

  def index
    authorize ::Crm::ServiceSchedule
    @service_schedules = policy_scope(::Crm::ServiceSchedule).order(:owner_type, :owner_id)
  end

  # Upsert per owner: one schedule per [account, owner] (LOCKED decision 5).
  def create
    owner = fetch_owner
    @service_schedule = ::Crm::ServiceSchedule.find_or_initialize_by(account_id: Current.account.id, owner: owner)
    @service_schedule.assign_attributes(schedule_attributes)
    authorize @service_schedule
    @service_schedule.save!
    render :show, status: :created
  end

  def update
    @service_schedule.update!(schedule_attributes)
    render :show
  end

  def destroy
    @service_schedule.destroy!
    head :no_content
  end

  private

  def fetch_schedule
    @service_schedule = ::Crm::ServiceSchedule.find_by!(account_id: Current.account.id, id: params[:id])
    authorize @service_schedule
  end

  # Owner is ALWAYS resolved inside Current.account (never a global find).
  def fetch_owner
    case permitted_params[:owner_type]
    when 'Inbox' then Current.account.inboxes.find(permitted_params[:owner_id])
    when 'User' then Current.account.users.find(permitted_params[:owner_id])
    else raise ActiveRecord::RecordNotFound
    end
  end

  # owner_type/owner_id are intentionally NOT included: a schedule's owner is
  # immutable after creation (no ownership-transfer path). Keep it that way.
  def schedule_attributes
    {
      timezone: permitted_params[:timezone],
      enabled: permitted_params.key?(:enabled) ? permitted_params[:enabled] : true,
      blocks: normalized_blocks
    }
  end

  # jsonb stores string keys; coerce minutes to Integer so model validation holds.
  def normalized_blocks
    Array(permitted_params[:blocks]).map do |block|
      { 'day_of_week' => block[:day_of_week].to_i, 'start_minute' => block[:start_minute].to_i, 'end_minute' => block[:end_minute].to_i }
    end
  end

  def permitted_params
    params.require(:service_schedule).permit(:owner_type, :owner_id, :timezone, :enabled, blocks: [:day_of_week, :start_minute, :end_minute])
  end
end
