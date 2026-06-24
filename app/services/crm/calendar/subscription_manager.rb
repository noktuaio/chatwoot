module Crm
  module Calendar
    # Ensures a live push-notification subscription (S7-B) for one calendar mailbox,
    # creating or renewing it before expiry and persisting a Crm::CalendarSyncState.
    # Google channels can't be renewed → re-created (old one stopped). Microsoft
    # subscriptions are PATCH-renewed. No-op when the provider is simulated or the
    # mailbox isn't a real calendar inbox. Best-effort — never raises to the caller.
    class SubscriptionManager
      GOOGLE_TTL_SECONDS = 7.days.to_i
      MS_TTL = 70.hours        # under the /me/events ~4230-min cap
      RENEW_BEFORE = 6.hours   # refresh when expiring within this
      LOCK_NAMESPACE = 3       # pg_advisory namespace (1/2 are used by booking)

      def self.ensure_for(inbox)
        new(inbox).ensure
      end

      def initialize(inbox)
        @inbox = inbox
        @email_channel = inbox&.channel
      end

      def ensure
        return unless eligible?

        # Serialize per inbox so two concurrent renewal runs can't both create a remote
        # channel/subscription (one would be untracked/unstoppable). The fresh? check is
        # RE-DONE inside the lock: another worker may have just (re)subscribed.
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{@inbox.id.to_i})")

          state = Crm::CalendarSyncState.find_or_initialize_by(inbox_id: @inbox.id)
          next if fresh?(state)

          case provider_key
          when :google then ensure_google(state)
          when :microsoft then ensure_microsoft(state)
          end
        end
      rescue StandardError => e
        Rails.logger.warn("CRM calendar subscription ensure failed (inbox #{@inbox&.id}): #{e.class.name}: #{e.message}")
        nil
      end

      private

      attr_reader :inbox, :email_channel

      def eligible?
        email_channel.is_a?(Channel::Email) && email_channel.calendar_enabled? &&
          (email_channel.google? || email_channel.microsoft?) && !simulated?
      end

      def simulated?
        provider_key == :google ? Crm::Config.calendar_google_simulate? : Crm::Config.calendar_ms_simulate?
      end

      def provider_key
        email_channel.microsoft? ? :microsoft : :google
      end

      def fresh?(state)
        state.persisted? && state.status_active? && state.provider == provider_key.to_s &&
          state.expires_at.present? && state.expires_at > Time.current + RENEW_BEFORE
      end

      def webhook_url(provider)
        base = ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
        "#{base}/webhooks/crm_calendar/#{provider}"
      end

      # Google: always (re-)create a fresh channel, then stop the previous one.
      def ensure_google(state)
        previous = { channel_id: state.channel_id, resource_id: state.resource_id }
        new_channel_id = SecureRandom.uuid
        token = SecureRandom.hex(24)

        result = Google::CalendarWatchService.new(channel: email_channel).watch(
          channel_id: new_channel_id, address: webhook_url('google'), token: token, ttl_seconds: GOOGLE_TTL_SECONDS
        )

        state.update!(
          account_id: inbox.account_id, provider: :google, status: :active,
          channel_id: new_channel_id, resource_id: result[:resource_id], verification_token: token,
          expires_at: expiration_from_ms(result[:expiration_ms])
        )
        stop_google(previous)
      end

      def stop_google(previous)
        return if previous[:channel_id].blank?

        Google::CalendarWatchService.new(channel: email_channel).stop(
          channel_id: previous[:channel_id], resource_id: previous[:resource_id]
        )
      rescue StandardError => e
        Rails.logger.warn("CRM calendar Google channel stop failed: #{e.class.name}")
      end

      # Microsoft: renew (PATCH) when we still hold a subscription id, else create.
      def ensure_microsoft(state)
        service = Microsoft::CalendarSubscriptionService.new(channel: email_channel)
        new_expiry = Time.current + MS_TTL

        if state.persisted? && state.channel_id.present? && service.renew(subscription_id: state.channel_id, expiration: new_expiry)
          state.update!(status: :active, expires_at: new_expiry)
          return
        end

        client_state = SecureRandom.hex(24)
        result = service.create(
          notification_url: webhook_url('microsoft'), client_state: client_state, expiration: new_expiry
        )
        state.update!(
          account_id: inbox.account_id, provider: :microsoft, status: :active,
          channel_id: result[:subscription_id], resource_id: nil, verification_token: client_state,
          expires_at: parse_time(result[:expiration]) || new_expiry
        )
      end

      def expiration_from_ms(ms)
        return Time.current + GOOGLE_TTL_SECONDS if ms.to_i.zero?

        Time.zone.at(ms.to_i / 1000)
      end

      def parse_time(value)
        return if value.blank?

        Time.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
