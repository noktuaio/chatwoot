# Shared filter predicates for CRM cards so the board (Crm::Kanban::BoardPayloadBuilder)
# and the list (Crm::Cards::FilterQuery) agree on every server-side filter. Adding a
# filter to only one path re-creates the historical "Status" board/list divergence, so
# every new param MUST be honored here and mirrored client-side in cardMatchesFilters
# (crmKanban.js) OR force a refetch-on-realtime. Per-filter realtime contract:
#   * client-predicate (mirrored in cardMatchesFilters): stage_ids, value_min/value_max,
#     stale_days, standalone, team_id, priority, inbox_id, owner_id, search, follow_up.
#   * server-only + refetch-on-realtime (cannot be derived from a single upsert payload):
#     responsible_kind (bot/none rely on the agent_bot_inbox join + conversation assignee)
#     and ai_pending (the pending-suggestion set is computed per board load).
module Crm::Cards::SharedFilters
  RESPONSIBLE_KINDS = %w[agent bot none].freeze

  def apply_stage_ids_filter(cards)
    ids = parse_stage_ids
    return cards if ids.blank?

    cards.where(stage_id: ids)
  end

  def apply_value_range_filter(cards)
    cards = cards.where('crm_cards.value_cents >= ?', value_cents_param(:value_min)) if value_cents_param(:value_min)
    cards = cards.where('crm_cards.value_cents <= ?', value_cents_param(:value_max)) if value_cents_param(:value_max)
    cards
  end

  def apply_stale_filter(cards)
    days = @params[:stale_days].presence&.to_i
    return cards if days.blank? || days <= 0

    cards.where('crm_cards.last_message_at IS NULL OR crm_cards.last_message_at < ?', days.days.ago)
  end

  def apply_team_filter(cards)
    return cards if @params[:team_id].blank?

    cards.where(team_id: @params[:team_id])
  end

  def apply_ai_pending_filter(cards)
    return cards unless ActiveModel::Type::Boolean.new.cast(@params[:ai_pending])

    cards.where(id: Crm::AiStageSuggestion.where(status: :pending).select(:card_id))
  end

  # responsible_kind maps the realtime "responsible" descriptor to SQL:
  #   agent -> a human is responsible (linked conversation assignee, or owner when standalone)
  #   bot   -> no human responsible, but the resolved inbox has an active agent bot
  #   none  -> no human responsible and no active agent bot
  def apply_responsible_filter(cards)
    kind = @params[:responsible_kind].to_s
    return cards unless RESPONSIBLE_KINDS.include?(kind)

    scoped = cards
             .joins('LEFT JOIN conversations ON conversations.id = crm_cards.conversation_id')
             .joins('LEFT JOIN agent_bot_inboxes ON agent_bot_inboxes.inbox_id = ' \
                    'COALESCE(conversations.inbox_id, crm_cards.inbox_id) AND agent_bot_inboxes.status = 0')
    case kind
    when 'agent'
      scoped.where(human_responsible_sql)
    when 'bot'
      scoped.where("NOT (#{human_responsible_sql})").where.not(agent_bot_inboxes: { id: nil })
    when 'none'
      scoped.where("NOT (#{human_responsible_sql})").where(agent_bot_inboxes: { id: nil })
    end
  end

  private

  # A human is responsible when the linked conversation has an assignee, or (for cards
  # without a linked conversation) when an owner is set. Mirrors Crm::Card#responsible_descriptor.
  def human_responsible_sql
    '(crm_cards.conversation_id IS NOT NULL AND conversations.assignee_id IS NOT NULL) OR ' \
      '(crm_cards.conversation_id IS NULL AND crm_cards.owner_id IS NOT NULL)'
  end

  def parse_stage_ids
    Array(@params[:stage_ids].presence || @params[:stage_id].presence)
      .flat_map { |stage_id| stage_id.to_s.split(',') }
      .filter_map { |stage_id| Integer(stage_id, exception: false) }
      .uniq
  end

  def value_cents_param(key)
    raw = @params[key]
    return if raw.blank?

    Integer(raw, exception: false)
  end
end
