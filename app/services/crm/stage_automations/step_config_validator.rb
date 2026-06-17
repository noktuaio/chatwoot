class Crm::StageAutomations::StepConfigValidator
  def initialize(step)
    @step = step
  end

  def validate
    case @step.action_type
    when 'create_follow_up'
      validate_create_follow_up!
    when 'assign_owner'
      validate_assign_owner!
    when 'move_stage'
      validate_move_stage!
    end
  end

  private

  def config
    (@step.action_config || {}).to_h.stringify_keys
  end

  def validate_create_follow_up!
    return if config['title'].to_s.strip.present?

    @step.errors.add(:action_config, 'title is required for create_follow_up steps')
  end

  def validate_assign_owner!
    return if config['owner_id'].present? || ActiveModel::Type::Boolean.new.cast(config['use_card_owner'])

    @step.errors.add(:action_config, 'owner_id or use_card_owner is required for assign_owner steps')
  end

  def validate_move_stage!
    return if config['target_stage_id'].present?

    @step.errors.add(:action_config, 'target_stage_id is required for move_stage steps')
  end
end
