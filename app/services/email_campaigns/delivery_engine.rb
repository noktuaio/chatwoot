module EmailCampaigns
  # Batch delivery respecting the SES max send rate. Idempotent: only sends to pending
  # recipients; skips suppressed; persists per-recipient ses_message_id/status/last_error;
  # refreshes counters; marks the campaign sent when no pending remain. Defensive: a single
  # recipient failure never strands the run.
  class DeliveryEngine
    BATCH_SIZE = 100
    SEND_INTERVAL = (1.0 / EmailCampaigns::DeliveryConfig.max_send_rate).seconds

    def initialize(campaign)
      @campaign = campaign
      @account = campaign.account
    end

    def perform
      return unless EmailCampaigns::Config.enabled?
      return unless eligible?
      return guardrail_pause! if EmailCampaigns::Guardrail.paused?(@account)

      @campaign.mark_sending! unless @campaign.sending?
      sender = EmailCampaigns::Ses::Sender.new(@campaign.sender_identity)
      suppressed = EmailSuppression.suppressed_set_for(@account)

      @campaign.email_campaign_recipients.pending.find_each(batch_size: BATCH_SIZE) do |recipient|
        break unless @campaign.reload.sending?

        deliver_one(recipient, sender, suppressed)
        sleep(SEND_INTERVAL) if SEND_INTERVAL.positive?
      end

      @campaign.finalize! if @campaign.reload.sending? && no_pending?
    end

    private

    def eligible?
      @campaign.reload
      return false unless @campaign.sending? || @campaign.scheduled?
      return false unless @campaign.sender_identity&.usable?

      true
    end

    # Tenant-level guardrail tripped (bounce/complaint over limit in the 7d window):
    # refuse to send and park the campaign with a clear, actionable error.
    def guardrail_pause!
      reason = @account.internal_attributes.dig(EmailCampaigns::Guardrail::FLAG_KEY, 'reason')
      @campaign.update!(status: :paused,
                        last_error: 'Envios pausados pelo guardrail de reputação da conta ' \
                                    "(#{reason}). Após resolver a causa, solicite a liberação do guardrail.")
    end

    def deliver_one(recipient, sender, suppressed)
      return recipient.mark_suppressed! if suppressed.include?(recipient.email.downcase)
      return unless claim(recipient)

      rendered = render(recipient)
      tracked_html = EmailCampaigns::Tracking::Injector.new(recipient, rendered[:body_html]).perform
      message_id = sender.deliver(
        to: recipient.email,
        subject: rendered[:subject],
        html_body: tracked_html,
        reply_to: @campaign.reply_to.presence || default_reply_to,
        from_email: from_email,
        headers: unsubscribe_headers(recipient)
      )
      # SES has ACCEPTED the message by here — never route a post-send failure through the
      # transient-retry path (that would re-queue + re-send a delivered message = duplicate email).
      persist_sent!(recipient, message_id)
    rescue StandardError => e
      Rails.logger.error("[EmailCampaigns::DeliveryEngine] campaign=#{@campaign.id} recipient=#{recipient.id} #{e.message}")
      handle_send_failure(recipient, e)
    ensure
      @campaign.refresh_counters!
    end

    # Post-send bookkeeping. The claim already flipped the row to :sent; persist the message_id.
    # If the local write blips, retry it a few times then give up WITHOUT re-queueing — the row
    # stays :sent (at-most-once), we only lose the ses_message_id linkage for that recipient.
    def persist_sent!(recipient, message_id)
      recipient.update_columns(ses_message_id: message_id, sent_at: Time.current, last_error: nil, updated_at: Time.current)
    rescue StandardError => e
      Rails.logger.error("[EmailCampaigns::DeliveryEngine] post-send persist failed campaign=#{@campaign.id} " \
                         "recipient=#{recipient.id} ses_message_id=#{message_id} #{e.message}")
    end

    # SES transient signals: throttling / 5xx / timeouts → requeue (claim is undone to pending,
    # attempts bumped) up to MAX_ATTEMPTS, then permanently failed. Permanent errors (bad
    # address, validation) fail immediately. at-most-once is preserved: a recipient whose SES
    # call SUCCEEDED never raises and is never reset.
    TRANSIENT_PATTERNS = /throttl|throttling|timeout|timed out|temporar|503|500|502|504|rate exceeded|service unavailable/i

    def handle_send_failure(recipient, error)
      if transient?(error)
        recipient.register_attempt!(error.message)
      else
        recipient.mark_failed!(error.message)
      end
    end

    def transient?(error)
      return true if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout) || error.is_a?(Timeout::Error)

      error.message.to_s.match?(TRANSIENT_PATTERNS)
    end

    # Atomically claim a pending recipient so concurrent runs cannot double-send.
    # Only the run whose UPDATE flips the row (pending -> sent) owns the delivery.
    def claim(recipient)
      claimed = EmailCampaignRecipient.where(id: recipient.id, status: EmailCampaignRecipient.statuses[:pending])
                                      .update_all(status: EmailCampaignRecipient.statuses[:sent], updated_at: Time.current)
      claimed.positive?
    end

    def render(recipient)
      renderer = EmailCampaigns::TemplateRenderer.new(recipient)
      { subject: renderer.render(@campaign.subject),
        body_html: inject_preheader(renderer.render(@campaign.body_html), renderer.render(@campaign.preheader)) }
    end

    # Inject a hidden preheader snippet right after <body> (or at the top of the html) so inbox
    # preview text shows the campaign's preheader. Padded with zero-width/non-breaking chars so the
    # client doesn't pull body content into the preview. The text is already rendered through the
    # TemplateRenderer (placeholders supported).
    def inject_preheader(html, preheader)
      return html if preheader.blank?

      snippet = '<div style="display:none;visibility:hidden;max-height:0;overflow:hidden;mso-hide:all;' \
                "font-size:0;line-height:0;color:transparent;\">#{preheader}#{'&zwnj;&nbsp;' * 60}</div>"
      if html =~ /<body[^>]*>/i
        html.sub(/(<body[^>]*>)/i) { "#{Regexp.last_match(1)}#{snippet}" }
      else
        snippet + html
      end
    end

    def from_email
      name = @campaign.from_name.presence
      addr = @campaign.from_email.presence || @campaign.sender_identity.from_email.presence
      addr.present? && name.present? ? "#{name} <#{addr}>" : addr
    end

    def default_reply_to
      @campaign.sender_identity.from_email.presence
    end

    # RFC 8058 one-click unsubscribe — real per-recipient public endpoint (raw URL, no click
    # tracking rewrap).
    def unsubscribe_headers(recipient)
      url = EmailCampaigns::Unsubscribe::Token.url(recipient)
      {
        'List-Unsubscribe' => "<#{url}>",
        'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click'
      }
    end

    def no_pending?
      !@campaign.email_campaign_recipients.pending.exists?
    end
  end
end
