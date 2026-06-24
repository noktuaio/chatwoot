class Api::V1::Accounts::Crm::ReportsController < Api::V1::Accounts::Crm::BaseController
  before_action :authorize_reports

  def pipelines
    options = Current.account.crm_pipelines.order(:position, :id).map do |pipeline|
      { id: pipeline.id, name: pipeline.name, is_default: pipeline.is_default }
    end
    render json: { payload: options }
  end

  def summary
    render_report(::Crm::Reports::Summary)
  end

  def funnel
    render_report(::Crm::Reports::Funnel)
  end

  def ai_vs_human
    render_report(::Crm::Reports::AiVsHuman)
  end

  def throughput
    render_report(::Crm::Reports::Throughput)
  end

  def follow_ups
    render_report(::Crm::Reports::FollowUps)
  end

  def workload
    render_report(::Crm::Reports::Workload)
  end

  def meetings
    unless Crm::Config.calendar_meetings_enabled?(Current.account)
      payload = ::Crm::Reports::Meetings.new(account: Current.account, params: report_params).empty_payload
      return render json: { payload: payload }
    end

    render_report(::Crm::Reports::Meetings)
  end

  private

  def authorize_reports
    authorize %i[crm report], :view?
  end

  def render_report(builder_class)
    payload = builder_class.new(account: Current.account, params: report_params).perform
    render json: { payload: payload }
  end

  def report_params
    params.permit(:pipeline_id, :since, :until, :group_by)
  end
end
