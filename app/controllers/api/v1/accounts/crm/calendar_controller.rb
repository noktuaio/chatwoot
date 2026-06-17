class Api::V1::Accounts::Crm::CalendarController < Api::V1::Accounts::Crm::BaseController
  def events
    authorize ::Crm::FollowUp, :index?
    render json: { payload: follow_up_events + expected_close_events }
  end

  private

  def follow_up_events
    filtered_follow_ups.order(:due_at, :id).limit(limit).map do |follow_up|
      {
        id: "follow_up_#{follow_up.id}",
        event_type: "follow_up_#{follow_up.automation_mode}",
        title: follow_up.title,
        starts_at: follow_up.due_at&.iso8601,
        status: follow_up.status,
        card_id: follow_up.card_id,
        conversation_id: visible_conversation_id(follow_up),
        contact_id: follow_up.contact_id,
        inbox_id: follow_up.inbox_id,
        assignee_id: follow_up.assignee_id
      }
    end
  end

  def expected_close_events
    filtered_cards.where.not(expected_close_at: nil).order(:expected_close_at, :id).limit(limit).map do |card|
      {
        id: "expected_close_#{card.id}",
        event_type: 'expected_close',
        title: card.title,
        starts_at: card.expected_close_at&.iso8601,
        status: card.status,
        card_id: card.id,
        conversation_id: visible_card_conversation_id(card),
        contact_id: card.contact_id,
        inbox_id: card.inbox_id,
        assignee_id: card.owner_id
      }
    end
  end

  def filtered_follow_ups
    ::Crm::FollowUps::FilterQuery.new(
      scope: policy_scope(::Crm::FollowUp),
      params: params,
      includes: [:card, { conversation: :conversation_participants }]
    ).perform
  end

  def filtered_cards
    ::Crm::Cards::CalendarQuery.new(scope: policy_scope(::Crm::Card), params: params).perform
  end

  def visible_conversation_id(follow_up)
    return if follow_up.conversation.blank?
    return follow_up.conversation_id if conversation_visibility.visible?(follow_up.conversation)
  end

  def visible_card_conversation_id(card)
    return if card.primary_conversation.blank?
    return card.conversation_id if conversation_visibility.visible?(card.primary_conversation)
  end

  def conversation_visibility
    @conversation_visibility ||= Crm::Conversations::Visibility.new(
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user
    )
  end

  def limit
    params.fetch(:limit, 200).to_i.clamp(1, 500)
  end
end
