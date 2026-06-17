class Crm::Pipeline < ApplicationRecord
  self.table_name = 'crm_pipelines'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :stages, class_name: 'Crm::PipelineStage', dependent: :destroy
  has_many :pipeline_inboxes, class_name: 'Crm::PipelineInbox', dependent: :destroy
  has_many :inboxes, through: :pipeline_inboxes
  has_many :cards, class_name: 'Crm::Card', dependent: :restrict_with_error

  enum status: { active: 0, archived: 1 }

  validates :name, presence: true
  validates :metadata, jsonb_attributes_length: true
end
