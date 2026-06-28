class Crm::Ai::UsageBroadcaster
  EVENT = 'crm.ai_usage.created'.freeze

  def self.broadcast(event)
    new(event).broadcast
  end

  def initialize(event)
    @event = event
  end

  def broadcast
    permitted_users.find_each do |user|
      next if user.pubsub_token.blank?

      ActionCable.server.broadcast(user.pubsub_token, { event: EVENT, data: payload })
    end
  rescue StandardError => e
    Rails.logger.warn("[crm][ai][usage] broadcast failed event_id=#{event.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :event

  def permitted_users
    User.where(id: permitted_account_user_ids)
  end

  def permitted_account_user_ids
    account_users.select { |account_user| report_policy(account_user).view? }.map(&:user_id)
  end

  def account_users
    AccountUser.human.where(account_id: event.account_id).includes(:user, :custom_role)
  end

  def report_policy(account_user)
    Crm::ReportPolicy.new(
      { user: account_user.user, account: event.account, account_user: account_user },
      %i[crm report]
    )
  end

  def payload
    {
      id: event.id,
      account_id: event.account_id,
      resource: Crm::Reports::AiUsage.resource_for_feature(event.feature),
      created_at: event.created_at.iso8601
    }.merge(token_payload)
  end

  def token_payload
    input = event.input_tokens.to_i
    output = event.output_tokens.to_i
    {
      input_tokens: input,
      cached_tokens: event.cached_tokens,
      output_tokens: output,
      total_tokens: input + output,
      cost_usd: event.cost_estimate.to_d.round(6).to_f
    }
  end
end
