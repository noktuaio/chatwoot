class Crm::StageAutomations::Runner
  def initialize(card:, actor:, from_stage_id:, to_stage_id:, exited_at: Time.current, automation_context: {})
    @card = card
    @actor = actor
    @from_stage_id = from_stage_id
    @to_stage_id = to_stage_id
    @exited_at = exited_at
    @automation_context = automation_context.to_h.with_indifferent_access
  end

  def perform
    return unless ::Crm::Config.enabled?
    return if @automation_context[:depth].to_i >= Crm::StageAutomations::StepExecutor::MAX_AUTOMATION_DEPTH

    run_for_stage(@from_stage_id, :on_exit) if @from_stage_id.present? && @from_stage_id != @to_stage_id
    run_for_stage(@to_stage_id, :on_enter) if @to_stage_id.present?
  end

  private

  def run_for_stage(stage_id, trigger_event)
    automations = @card.account.crm_stage_automations
                       .enabled
                       .where(stage_id: stage_id, trigger_event: trigger_event)
                       .includes(:steps)
                       .ordered

    automations.find_each do |automation|
      run_automation(automation, stage_id, trigger_event)
    end
  end

  def run_automation(automation, stage_id, trigger_event)
    trigger_token = build_trigger_token(stage_id, trigger_event)
    execution = find_or_create_execution!(automation, trigger_token)
    return if execution.completed? || execution.failed?

    step_results = []
    automation.steps.ordered.each do |step|
      result = run_step(step, execution)
      step_results << { step_id: step.id, status: result.status, error: result.error, payload: result.payload }
      next if result.status == :ok

      execution.update!(status: :failed, error_message: result.error.to_s, completed_at: Time.current,
                        metadata: execution.metadata.merge('step_results' => step_results))
      return
    end

    execution.update!(
      status: :completed,
      completed_at: Time.current,
      metadata: execution.metadata.merge('step_results' => step_results)
    )
  end

  def run_step(step, execution)
    if step.delay_seconds.positive? && step.action_type != 'create_follow_up'
      enqueue_delayed_step(step, execution)
      Crm::StageAutomations::StepExecutor::Result.ok(scheduled: true)
    elsif step.delay_seconds.positive?
      Crm::StageAutomations::StepExecutor.new(
        card: @card.reload,
        step: step,
        actor: @actor,
        automation_context: @automation_context
      ).perform
    else
      Crm::StageAutomations::StepExecutor.new(
        card: @card.reload,
        step: step,
        actor: @actor,
        automation_context: @automation_context
      ).perform
    end
  end

  def enqueue_delayed_step(step, execution)
    Crm::StageAutomationStepJob.set(wait: step.delay_seconds.seconds).perform_later(
      card_id: @card.id,
      step_id: step.id,
      actor_id: @actor&.id,
      execution_id: execution.id,
      automation_context: @automation_context
    )
  end

  def find_or_create_execution!(automation, trigger_token)
    existing = @card.account.crm_stage_automation_executions.find_by(
      card_id: @card.id,
      stage_automation_id: automation.id,
      trigger_token: trigger_token
    )
    return existing if existing.present?

    @card.account.crm_stage_automation_executions.create!(
      card: @card,
      stage_automation: automation,
      trigger_token: trigger_token,
      status: :running
    )
  end

  def build_trigger_token(stage_id, trigger_event)
    if trigger_event.to_s == 'on_enter'
      Crm::StageAutomations::TriggerToken.for_enter(card: @card, stage_id: stage_id)
    else
      Crm::StageAutomations::TriggerToken.for_exit(
        card: @card,
        from_stage_id: stage_id,
        exited_at: @exited_at
      )
    end
  end
end
