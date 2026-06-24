module EmailCampaigns
  module Reports
    class Builder
      PEOPLE_LIMIT = 100
      TIMELINE_INTERVALS = %w[hour day].freeze
      TIMELINE_EVENT_TYPES = %w[delivered open click].freeze
      TIMELINE_CAP = 30.days

      def initialize(account:, params: {})
        @account = account
        @params = params || {}
      end

      def campaigns
        scope.order(created_at: :desc).map do |c|
          kpis(c).merge(id: c.id, name: c.name, subject: c.subject, status: c.status, created_at: c.created_at)
        end
      end

      # Aggregate KPIs over the (optionally campaign-filtered) scope. Rates derived from the totals.
      def summary
        totals = Hash.new(0)
        scope.find_each { |c| kpis(c).each { |k, v| totals[k] += v if v.is_a?(Numeric) } }
        totals.merge(rates(totals))
      end

      def campaign_detail(id)
        campaign = scope.find_by(id: id)
        return nil if campaign.nil?

        k = kpis(campaign)
        k.merge(
          id: campaign.id, name: campaign.name, subject: campaign.subject, status: campaign.status,
          rates: rates(k), opened: people(campaign, :open), clicked: people(campaign, :click)
        )
      end

      # Click events grouped by URL: total clicks + unique clickers (distinct recipients).
      def clicks_by_url(campaign)
        clicks = campaign.email_events.clicks.where.not(url: [nil, ''])
        totals = clicks.group(:url).count
        uniques = clicks.group(:url).distinct.count(:recipient_id)
        totals.map { |url, total| { url: url, total_clicks: total, unique_clicks: uniques[url].to_i } }
              .sort_by { |row| -row[:total_clicks] }
      end

      # delivered/open/click series bucketed by date_trunc(interval, occurred_at),
      # from sent_at (fallback created_at) until now, capped at 30 days back.
      def timeline(campaign, interval: 'day')
        interval = TIMELINE_INTERVALS.include?(interval.to_s) ? interval.to_s : 'day'
        # Lower bound on created_at (sempre anterior a qualquer evento), NÃO em sent_at: no envio
        # direto os eventos ocorrem antes do finalize! (que grava sent_at=agora) e no SES os
        # 'delivered' que chegam durante um envio longo são anteriores ao sent_at final — usar
        # sent_at cortava esses eventos e zerava o gráfico.
        since = [campaign.created_at, TIMELINE_CAP.ago].max
        rows = campaign.email_events
                       .where(event_type: TIMELINE_EVENT_TYPES, occurred_at: since..Time.current)
                       .group(Arel.sql("date_trunc('#{interval}', occurred_at)"), :event_type)
                       .count
        buckets = Hash.new { |h, k| h[k] = { 'delivered' => 0, 'open' => 0, 'click' => 0 } }
        rows.each { |(bucket, type), count| buckets[bucket][type] = count }
        series = buckets.sort.map do |bucket, counts|
          { bucket: bucket.iso8601, delivered: counts['delivered'], open: counts['open'], click: counts['click'] }
        end
        { interval: interval, since: since.iso8601, series: series }
      end

      private

      def scope
        s = EmailCampaign.where(account_id: @account.id)
        s = s.where(id: @params[:campaign_id]) if @params[:campaign_id].present?
        s
      end

      def kpis(campaign)
        {
          recipients: campaign.recipients_count, sent: campaign.sent_count, delivered: campaign.delivered_count,
          opened: campaign.opened_count, clicked: campaign.clicked_count, bounced: campaign.bounced_count,
          complained: campaign.complained_count, unsubscribed: campaign.unsubscribed_count,
          failed: campaign.failed_count, suppressed: campaign.suppressed_count
        }
      end

      # Rates over DELIVERED (PRD §6). Guards divide-by-zero.
      def rates(k)
        base = k[:delivered].to_i
        return zero_rates if base.zero?

        {
          open_rate: pct(k[:opened], base), click_rate: pct(k[:clicked], base),
          bounce_rate: pct(k[:bounced], base), complaint_rate: pct(k[:complained], base),
          unsubscribe_rate: pct(k[:unsubscribed], base)
        }
      end

      def zero_rates
        { open_rate: 0.0, click_rate: 0.0, bounce_rate: 0.0, complaint_rate: 0.0, unsubscribe_rate: 0.0 }
      end

      def pct(numerator, base)
        ((numerator.to_f / base) * 100).round(2)
      end

      # Recent recipients with an event of the given type (who opened / who clicked).
      def people(campaign, type)
        EmailCampaignRecipient.where(email_campaign_id: campaign.id)
                              .joins(:email_events)
                              .where(email_events: { event_type: EmailEvent.event_types[type.to_s] })
                              .distinct
                              .order(last_event_at: :desc)
                              .limit(PEOPLE_LIMIT)
                              .map { |r| { id: r.id, name: r.name, email: r.email, last_event_at: r.last_event_at } }
      end
    end
  end
end
