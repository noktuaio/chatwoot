class Api::V1::Accounts::EmailCampaigns::TemplateToolsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_campaign

  def placeholders
    render json: { placeholders: EmailCampaigns::TemplateValidator.new(@campaign).available }
  end

  def validate
    render json: EmailCampaigns::TemplateValidator.new(@campaign).perform
  end

  private

  def fetch_campaign
    @campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    authorize @campaign, :show?
  end
end
