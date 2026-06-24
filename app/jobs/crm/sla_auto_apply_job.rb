class Crm::SlaAutoApplyJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    account = conversation.account
    return unless account.feature_enabled?('sla')
    return if conversation.sla_policy_id.present?

    policy = account.sla_policies.order(:id).detect { |sla_policy| applies?(sla_policy, conversation) }
    return if policy.blank?

    Rails.logger.info "SLA:: Auto-applying SLA #{policy.id} to conversation: #{conversation.id}"
    conversation.update!(sla_policy_id: policy.id)
  rescue StandardError => e
    Rails.logger.warn "SLA:: Auto-apply failed for conversation #{conversation_id}: #{e.message}"
  end

  private

  # LOCKED decision 4: policy applies when auto-apply is enabled for
  # conversation_created AND (both lists empty = all) OR the conversation inbox
  # is selected OR the inbox belongs to a selected pipeline (Crm::PipelineInbox).
  def applies?(sla_policy, conversation)
    config = sla_policy.auto_apply_config
    return false unless config['enabled'] && config['event'] == 'conversation_created'
    return false if sla_policy.exclude_groups? && Crm::WhatsappGroupDetector.group_conversation?(conversation)

    inbox_ids = config['inbox_ids']
    pipeline_ids = config['pipeline_ids']
    return true if inbox_ids.empty? && pipeline_ids.empty?
    return true if inbox_ids.include?(conversation.inbox_id)

    pipeline_ids.any? && Crm::PipelineInbox.exists?(account_id: conversation.account_id, pipeline_id: pipeline_ids, inbox_id: conversation.inbox_id)
  end
end
