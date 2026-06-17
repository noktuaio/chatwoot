class Crm::PipelineInbox < ApplicationRecord
  self.table_name = 'crm_pipeline_inboxes'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :inbox
  belongs_to :default_stage, class_name: 'Crm::PipelineStage', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  validates :inbox_id, uniqueness: { scope: [:account_id, :pipeline_id] }
  validate :linked_records_must_belong_to_account
  validate :default_stage_must_belong_to_pipeline

  private

  def linked_records_must_belong_to_account
    validate_same_account(:pipeline)
    validate_same_account(:inbox)
    validate_same_account(:default_stage)
  end

  def default_stage_must_belong_to_pipeline
    return if default_stage.blank? || pipeline.blank?
    return if default_stage.pipeline_id == pipeline_id

    errors.add(:default_stage, 'must belong to the selected pipeline')
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
