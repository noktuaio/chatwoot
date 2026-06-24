class Api::V1::Accounts::Crm::ServiceSchedulesController < Api::V1::Accounts::Crm::BaseController
  # Calendários de serviço fazem parte do SLA: além do gate de CRM (BaseController), exigem a feature
  # `sla` da conta — senão a API some (404), alinhado à UI (que gate em FEATURE_FLAGS.SLA).
  before_action :ensure_sla_enabled
  before_action :fetch_schedule, only: [:update, :destroy]

  def index
    authorize ::Crm::ServiceSchedule
    @service_schedules = policy_scope(::Crm::ServiceSchedule).order(:owner_type, :owner_id)
  end

  # Upsert per owner: one schedule per [account, owner] (LOCKED decision 5).
  def create
    owner = fetch_owner
    @service_schedule = ::Crm::ServiceSchedule.find_or_initialize_by(account_id: Current.account.id, owner: owner)
    @service_schedule.assign_attributes(create_attributes)
    authorize @service_schedule
    @service_schedule.save!
    render :show, status: :created
  rescue ActiveRecord::RecordNotUnique
    # Corrida no upsert vencida pelo índice único do banco → update idempotente.
    upsert_existing_owner(owner)
  rescue ActiveRecord::RecordInvalid => e
    # Corrida vencida ANTES do insert pela validação Rails de uniqueness (owner_id taken) → idem.
    # Qualquer outro erro de validação (blocks/timezone) re-levanta p/ virar 422 normal.
    raise e unless e.record.errors.of_kind?(:owner_id, :taken)

    upsert_existing_owner(owner)
  end

  def update
    @service_schedule.update!(update_attributes)
    render :show
  end

  def destroy
    @service_schedule.destroy!
    head :no_content
  end

  private

  def ensure_sla_enabled
    render json: { error: 'sla.disabled' }, status: :not_found unless Current.account.feature_enabled?('sla')
  end

  def fetch_schedule
    @service_schedule = ::Crm::ServiceSchedule.find_by!(account_id: Current.account.id, id: params[:id])
    authorize @service_schedule
  end

  # Idempotent upsert when a create lost the per-owner race (either DB unique index or Rails
  # uniqueness validation): re-find the existing row and apply the same attributes.
  def upsert_existing_owner(owner)
    @service_schedule = ::Crm::ServiceSchedule.find_by!(account_id: Current.account.id, owner: owner)
    authorize @service_schedule, :update? # semanticamente é um update (a linha já existe pela corrida)
    @service_schedule.update!(create_attributes)
    render :show
  end

  # Owner is ALWAYS resolved inside Current.account (never a global find). For User owners we use
  # Account#agents (integration:false) so a schedule can't be attached to a bot/integration user.
  def fetch_owner
    case permitted_params[:owner_type]
    when 'Inbox' then Current.account.inboxes.find(permitted_params[:owner_id])
    when 'User' then Current.account.agents.find(permitted_params[:owner_id])
    else raise ActiveRecord::RecordNotFound
    end
  end

  # owner_type/owner_id are intentionally NOT included: a schedule's owner is immutable after creation
  # (no ownership-transfer path). CREATE applies defaults (enabled=true, blocks=[]); timezone is
  # required (presence validation catches a missing one).
  def create_attributes
    {
      timezone: permitted_params[:timezone],
      enabled: permitted_params.key?(:enabled) ? permitted_params[:enabled] : true,
      blocks: permitted_params.key?(:blocks) ? normalized_blocks : []
    }
  end

  # UPDATE (PATCH) is PARTIAL: only the keys actually sent are overwritten, so a PATCH carrying just
  # `enabled` can't wipe the existing timezone/blocks (which the old code did by always rewriting all).
  def update_attributes
    {}.tap do |attrs|
      attrs[:timezone] = permitted_params[:timezone] if permitted_params.key?(:timezone)
      attrs[:enabled] = permitted_params[:enabled] if permitted_params.key?(:enabled)
      attrs[:blocks] = normalized_blocks if permitted_params.key?(:blocks)
    end
  end

  # jsonb stores string keys; coerce minutes to Integer so model validation holds. A non-integer
  # value (garbage) is kept AS-IS (NOT silently coerced to 0 by to_i) so the model rejects it (422).
  def normalized_blocks
    Array(permitted_params[:blocks]).map do |block|
      {
        'day_of_week' => coerce_integer(block[:day_of_week]),
        'start_minute' => coerce_integer(block[:start_minute]),
        'end_minute' => coerce_integer(block[:end_minute])
      }
    end
  end

  def coerce_integer(value)
    Integer(value.to_s, 10)
  rescue ArgumentError, TypeError
    value # keep the raw (non-integer) value so blocks_must_be_well_formed rejects it
  end

  def permitted_params
    params.require(:service_schedule).permit(:owner_type, :owner_id, :timezone, :enabled, blocks: [:day_of_week, :start_minute, :end_minute])
  end
end
