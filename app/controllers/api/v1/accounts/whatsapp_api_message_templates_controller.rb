class Api::V1::Accounts::WhatsappApiMessageTemplatesController < Api::V1::Accounts::BaseController
  before_action :ensure_whatsapp_api_campaigns_enabled
  before_action :fetch_inbox
  before_action :fetch_template, only: [:update, :destroy]
  before_action :check_authorization

  def index
    @whatsapp_api_message_templates = Current.account.whatsapp_api_message_templates
                                                   .active
                                                   .for_inbox(@inbox.id)
                                                   .order(:name)
  end

  def create
    @whatsapp_api_message_template = Current.account.whatsapp_api_message_templates.create!(
      template_params.merge(inbox: @inbox, created_by: Current.user)
    )
    render :show, status: :created
  end

  def update
    @whatsapp_api_message_template.update!(template_params.merge(updated_by: Current.user))
    render :show
  end

  def destroy
    @whatsapp_api_message_template.archive!
    head :no_content
  end

  private

  def ensure_whatsapp_api_campaigns_enabled
    render json: { error: 'whatsapp_api_campaigns.disabled' }, status: :not_found unless WhatsappApiCampaigns::Config.enabled?
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    return if @inbox.api? && @inbox.channel.whatsapp_api_campaign_channel?

    render json: { error: 'whatsapp_api_campaigns.inbox_not_enabled' }, status: :not_found and return
  end

  def fetch_template
    @whatsapp_api_message_template = Current.account.whatsapp_api_message_templates.active.for_inbox(@inbox.id).find(params[:id])
  end

  def template_params
    params.require(:template).permit(:name, :body)
  end
end
