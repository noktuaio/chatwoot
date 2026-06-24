# Shareable CRM list views (Lista & Calendário v2). A saved view captures a
# pipeline's list configuration — visible columns, filters, sort, group-by and
# density — under `config` and exposes it per visibility (private/team/account).
class Api::V1::Accounts::Crm::SavedViewsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_saved_view, only: [:update, :destroy]

  def index
    authorize ::Crm::SavedView
    @saved_views = policy_scope(::Crm::SavedView).ordered
    @saved_views = @saved_views.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
  end

  def create
    authorize ::Crm::SavedView
    @saved_view = ::Crm::SavedView.new(saved_view_params)
    @saved_view.account = Current.account
    @saved_view.user = Current.user
    @saved_view.save!
    render :show, status: :created
  end

  def update
    authorize @saved_view
    @saved_view.update!(saved_view_params)
    render :show
  end

  def destroy
    authorize @saved_view
    @saved_view.destroy!
    head :ok
  end

  private

  def fetch_saved_view
    @saved_view = policy_scope(::Crm::SavedView).find(params[:id])
  end

  def saved_view_params
    parameter_set(:saved_view).permit(:name, :pipeline_id, :visibility, :position, config: {})
  end
end
