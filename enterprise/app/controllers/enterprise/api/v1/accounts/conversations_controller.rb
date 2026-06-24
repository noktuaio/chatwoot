module Enterprise::Api::V1::Accounts::ConversationsController
  extend ActiveSupport::Concern

  def inbox_assistant
    assistant = @conversation.inbox.captain_assistant

    if assistant
      render json: { assistant: { id: assistant.id, name: assistant.name } }
    else
      render json: { assistant: nil }
    end
  end

  def reporting_events
    @reporting_events = @conversation.reporting_events.order(created_at: :asc)
  end

  def permitted_update_params
    # sla_policy_id só é aceito quando a conta tem a feature `sla`; sem ela, nem a coluna FK inerte
    # pode ser setada via API direta (gate consistente com controllers/jobs/callback de SLA).
    return super unless Current.account.feature_enabled?('sla')

    super.merge(params.permit(:sla_policy_id))
  end

  private

  def copilot_params
    params.permit(:previous_history, :message, :assistant_id)
  end
end
