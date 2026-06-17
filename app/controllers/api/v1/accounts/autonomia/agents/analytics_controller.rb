class Api::V1::Accounts::Autonomia::Agents::AnalyticsController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent

  def index
    @analytics = ::Autonomia::Agents::Analytics.new(agent: @agent, range: params[:range]).call
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:id]) # agents_scope = conta corrente -> isolamento
  end
end
