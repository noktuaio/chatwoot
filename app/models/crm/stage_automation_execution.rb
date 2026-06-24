class Crm::StageAutomationExecution < ApplicationRecord
  self.table_name = 'crm_stage_automation_executions'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :stage_automation, class_name: 'Crm::StageAutomation'

  enum status: { running: 0, completed: 1, failed: 2 }

  validates :trigger_token, presence: true
  validates :metadata, jsonb_attributes_length: true
end
