class Crm::StageAutomationStepJob < ApplicationJob
  queue_as :default

  def perform(card_id:, step_id:, actor_id: nil, execution_id: nil, automation_context: {})
    return unless ::Crm::Config.enabled?

    card = Crm::Card.find_by(id: card_id)
    step = Crm::StageAutomationStep.find_by(id: step_id)
    return if card.blank? || step.blank?

    actor = actor_id.present? ? User.find_by(id: actor_id) : nil
    result = Crm::StageAutomations::StepExecutor.new(
      card: card,
      step: step,
      actor: actor,
      automation_context: automation_context
    ).perform

    update_execution!(execution_id, result) if execution_id.present?
  end

  private

  def update_execution!(execution_id, result)
    execution = Crm::StageAutomationExecution.find_by(id: execution_id)
    return if execution.blank?

    step_results = execution.metadata.to_h['step_results'] || []
    step_results << { status: result.status, error: result.error, payload: result.payload, async: true }

    if result.status == :failed
      execution.update!(status: :failed, error_message: result.error.to_s, completed_at: Time.current,
                        metadata: execution.metadata.merge('step_results' => step_results))
    else
      execution.update!(metadata: execution.metadata.merge('step_results' => step_results))
    end
  end
end
