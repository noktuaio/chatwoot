class Crm::AiStageSuggestion < ApplicationRecord
  self.table_name = 'crm_ai_stage_suggestions'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :from_stage, class_name: 'Crm::PipelineStage'
  belongs_to :to_stage, class_name: 'Crm::PipelineStage'

  enum status: { pending: 0, accepted: 1, dismissed: 2, auto_applied: 3, expired: 4 }

  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :reasoning, length: { maximum: 500 }, allow_nil: true
  validates :model_used, presence: true
  validates :metadata, jsonb_attributes_length: true
  validate :stages_must_belong_to_account

  scope :current_pending, -> { where(status: :pending).order(created_at: :desc) }

  private

  def stages_must_belong_to_account
    return if account_id.blank?

    [from_stage, to_stage].compact.each do |stage|
      next if stage.account_id == account_id

      errors.add(:base, 'stages must belong to the same account')
      break
    end
  end
end
