class Crm::Cards::ConversationDefaultsResolver
  def initialize(account:, requested:, conversation:)
    @account = account
    @requested = requested
    @conversation = conversation
  end

  def perform
    pipeline = resolve_pipeline
    stage = resolve_stage(pipeline)
    raise ActiveRecord::RecordNotFound if pipeline.blank? || stage.blank?

    { pipeline_id: pipeline.id, stage_id: stage.id }
  end

  private

  def resolve_pipeline
    return @account.crm_pipelines.find(@requested[:pipeline_id]) if @requested[:pipeline_id].present?

    setting = @account.crm_inbox_settings.find_by(inbox_id: @conversation.inbox_id)
    setting&.default_pipeline || @account.crm_pipelines.active.order(:position, :id).first
  end

  def resolve_stage(pipeline)
    return @account.crm_pipeline_stages.where(pipeline: pipeline).find(@requested[:stage_id]) if @requested[:stage_id].present?

    pipeline_inbox = @account.crm_pipeline_inboxes.find_by(pipeline: pipeline, inbox_id: @conversation.inbox_id)
    pipeline_inbox&.default_stage || pipeline.stages.order(:position, :id).first
  end
end
