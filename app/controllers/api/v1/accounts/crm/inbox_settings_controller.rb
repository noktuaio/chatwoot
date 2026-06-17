class Api::V1::Accounts::Crm::InboxSettingsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_inbox, only: [:update]

  def index
    authorize ::Crm::InboxSetting
    @inbox_settings = policy_scope(::Crm::InboxSetting).includes(:inbox, :default_pipeline, :default_stage).order(:inbox_id)
    @inbox_settings_count = @inbox_settings.count
  end

  def update
    @inbox_setting = Current.account.crm_inbox_settings.find_or_initialize_by(inbox: @inbox)
    authorize @inbox_setting
    @inbox_setting.update!(inbox_setting_params)
    render :show
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def inbox_setting_params
    parameter_set(:inbox_setting).permit(
      :crm_enabled, :default_pipeline_id, :default_stage_id, :visibility_mode,
      :auto_create_card
    )
  end
end
