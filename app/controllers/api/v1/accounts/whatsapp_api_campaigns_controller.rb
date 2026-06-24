class Api::V1::Accounts::WhatsappApiCampaignsController < Api::V1::Accounts::BaseController
  before_action :ensure_whatsapp_api_campaigns_enabled
  before_action :set_current_page, only: [:index]
  before_action :fetch_campaign, only: [:show, :pause, :resume, :cancel]
  before_action :check_authorization

  RESULTS_PER_PAGE = 25

  def index
    @whatsapp_api_campaigns = Current.account.whatsapp_api_campaigns
                                             .includes(:inbox, :created_by, :whatsapp_api_campaign_recipients)
                                             .order(created_at: :desc)
                                             .page(@current_page)
                                             .per(RESULTS_PER_PAGE)
    @whatsapp_api_campaigns_count = Current.account.whatsapp_api_campaigns.count
  end

  def show; end

  def create
    @whatsapp_api_campaign = WhatsappApiCampaigns::Creator.new(
      account: Current.account,
      user: Current.user,
      params: normalized_create_params
    ).perform
    render :show, status: :created
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def pause
    @whatsapp_api_campaign.pause!
    render :show
  end

  def resume
    @whatsapp_api_campaign.resume!
    render :show
  end

  def cancel
    @whatsapp_api_campaign.cancel!
    render :show
  end

  private

  def ensure_whatsapp_api_campaigns_enabled
    render json: { error: 'whatsapp_api_campaigns.disabled' }, status: :not_found unless WhatsappApiCampaigns::Config.enabled?
  end

  def fetch_campaign
    @whatsapp_api_campaign = Current.account.whatsapp_api_campaigns.find(params[:id])
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def normalized_create_params
    permitted_params = params.permit(:title, :inbox_id, :template_id, :message_body, :scheduled_at, :media_file, audience: [:type, :id])
    permitted_params[:audience] = parsed_audience if params[:audience].is_a?(String)
    permitted_params
  end

  def parsed_audience
    JSON.parse(params[:audience])
  rescue JSON::ParserError
    []
  end
end
