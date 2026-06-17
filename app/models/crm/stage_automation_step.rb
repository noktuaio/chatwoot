class Crm::StageAutomationStep < ApplicationRecord
  self.table_name = 'crm_stage_automation_steps'

  belongs_to :account
  belongs_to :stage_automation, class_name: 'Crm::StageAutomation', inverse_of: :steps

  enum action_type: { create_follow_up: 0, assign_owner: 1, move_stage: 2 }

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :delay_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :action_config, jsonb_attributes_length: true
  validate :action_config_must_be_valid

  scope :ordered, -> { order(:position, :id) }

  private

  def action_config_must_be_valid
    Crm::StageAutomations::StepConfigValidator.new(self).validate
  end
end
