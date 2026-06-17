require 'csv'

class Api::V1::Accounts::EmailCampaigns::ReportsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :authorize_reports
  before_action :fetch_campaign, only: [:clicks, :timeline, :recipients, :export]

  RECIPIENTS_PER_PAGE = 50
  EXPORT_LIMIT = 10_000

  # GET .../email_campaigns/reports  — per-account campaign list + aggregate KPIs.
  # Optional ?campaign_id= narrows the summary + list to a single campaign.
  def index
    @summary = builder.summary
    @campaigns = builder.campaigns
  end

  # GET .../email_campaigns/reports/:id  — one campaign: KPIs + rates + who opened / who clicked.
  def show
    @detail = builder.campaign_detail(params[:id])
    return render json: { error: 'email_campaign.not_found' }, status: :not_found if @detail.nil?
  end

  # GET .../email_campaigns/reports/:id/clicks — click events grouped by URL (unique + total).
  def clicks
    @clicks = builder.clicks_by_url(@campaign)
  end

  # GET .../email_campaigns/reports/:id/timeline?interval=hour|day — delivered/open/click series.
  def timeline
    @timeline = builder.timeline(@campaign, interval: params[:interval])
  end

  # GET .../email_campaigns/reports/:id/recipients?page=&q= — paginated recipient drilldown.
  def recipients
    @current_page = (params[:page] || 1).to_i
    scope = recipients_scope
    @recipients_count = scope.count
    @recipients = scope.order(:id).page(@current_page).per(RECIPIENTS_PER_PAGE)
    @event_counts = event_counts_for(@recipients.map(&:id))
  end

  # GET .../email_campaigns/reports/:id/export — recipient drilldown as CSV.
  def export
    rows = recipients_scope.order(:id).limit(EXPORT_LIMIT).to_a
    counts = event_counts_for(rows.map(&:id))
    send_data "\xEF\xBB\xBF" + recipients_csv(rows, counts), type: 'text/csv; charset=utf-8',
                                                            filename: "email_campaign_#{@campaign.id}_recipients.csv"
  end

  private

  def authorize_reports
    authorize EmailCampaign, :view?, policy_class: EmailCampaignReportPolicy
  end

  def fetch_campaign
    @campaign = EmailCampaign.where(account_id: Current.account.id).find_by(id: params[:id])
    render json: { error: 'email_campaign.not_found' }, status: :not_found if @campaign.nil?
  end

  def recipients_scope
    scope = @campaign.email_campaign_recipients
    if params[:q].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope = scope.where('email ILIKE :term OR name ILIKE :term', term: term)
    end
    scope
  end

  def event_counts_for(recipient_ids)
    {
      opens: EmailEvent.opens.where(recipient_id: recipient_ids).group(:recipient_id).count,
      clicks: EmailEvent.clicks.where(recipient_id: recipient_ids).group(:recipient_id).count
    }
  end

  def recipients_csv(rows, counts)
    CSV.generate do |csv|
      csv << %w[id name email status attempts last_event_at opens clicks]
      rows.each do |r|
        csv << [r.id, csv_safe(r.name), csv_safe(r.email), r.status, r.attempts, r.last_event_at&.iso8601,
                counts[:opens][r.id].to_i, counts[:clicks][r.id].to_i]
      end
    end
  end

  # Prefix a leading apostrophe on cells starting with =,+,-,@ to neutralize CSV/formula injection.
  def csv_safe(value)
    str = value.to_s
    str.match?(/\A[=+\-@]/) ? "'#{str}" : str
  end

  def builder
    @builder ||= EmailCampaigns::Reports::Builder.new(account: Current.account, params: report_params)
  end

  def report_params
    params.permit(:campaign_id, :since, :until)
  end
end
