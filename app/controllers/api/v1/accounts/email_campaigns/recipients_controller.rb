class Api::V1::Accounts::EmailCampaigns::RecipientsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_campaign
  before_action :set_current_page, only: [:index]

  RESULTS_PER_PAGE = 50

  def index
    @recipients = @campaign.email_campaign_recipients
                           .order(:id)
                           .page(@current_page).per(RESULTS_PER_PAGE)
    @recipients_count = @campaign.email_campaign_recipients.count
  end

  def create
    return render_unprocessable('email_campaign.import_file_required') if params[:import_file].blank?
    return render_unprocessable('email_campaign.file_too_large') if too_large?
    return render_unprocessable('email_campaign.not_editable') unless @campaign.draft?

    @result = EmailCampaigns::RecipientImporter.new(
      @campaign, params[:import_file], filename: params[:import_file].original_filename
    ).perform
    @campaign.reload
    @recipients = @campaign.email_campaign_recipients.order(:id).page(1).per(RESULTS_PER_PAGE)
    @recipients_count = @campaign.email_campaign_recipients.count
    @current_page = 1
    render :index
  rescue EmailCampaigns::RecipientImporter::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_campaign
    @campaign = EmailCampaign.where(account: Current.account).find(params[:campaign_id])
    authorize @campaign, :show?
  end

  def too_large?
    params[:import_file].size > CampaignImports::Config.max_file_size_bytes
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
