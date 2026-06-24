class Crm::PipelineStage < ApplicationRecord
  self.table_name = 'crm_pipeline_stages'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline'

  has_many :cards, class_name: 'Crm::Card', foreign_key: :stage_id, dependent: :restrict_with_error, inverse_of: :stage
  has_many :stage_automations, class_name: 'Crm::StageAutomation', foreign_key: :stage_id, dependent: :destroy

  validates :name, presence: true
  validates :position, numericality: { only_integer: true }
  validates :win_probability, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :metadata, jsonb_attributes_length: true
  validate :pipeline_must_belong_to_account

  private

  def pipeline_must_belong_to_account
    return if pipeline.blank? || account_id.blank?
    return if pipeline.account_id == account_id

    errors.add(:pipeline, 'must belong to the same account')
  end
end
