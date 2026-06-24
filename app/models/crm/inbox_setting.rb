class Crm::InboxSetting < ApplicationRecord
  self.table_name = 'crm_inbox_settings'

  belongs_to :account
  belongs_to :inbox
  belongs_to :default_pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :default_stage, class_name: 'Crm::PipelineStage', optional: true

  enum visibility_mode: { all_inbox_cards: 0, assigned_only: 1 }

  validates :inbox_id, uniqueness: { scope: :account_id }
  validate :linked_records_must_belong_to_account
  validate :default_stage_must_belong_to_default_pipeline

  private

  def linked_records_must_belong_to_account
    validate_same_account(:inbox)
    validate_same_account(:default_pipeline)
    validate_same_account(:default_stage)
  end

  def default_stage_must_belong_to_default_pipeline
    return if default_stage.blank? || default_pipeline.blank?
    return if default_stage.pipeline_id == default_pipeline_id

    errors.add(:default_stage, 'must belong to the selected default pipeline')
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
