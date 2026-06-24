# == Schema Information
#
# Table name: sla_policies
#
#  id                            :bigint           not null, primary key
#  ai_skip_natural_pause         :boolean          default(TRUE), not null
#  auto_apply                    :jsonb            not null
#  description                   :string
#  exclude_groups                :boolean          default(TRUE), not null
#  first_response_time_threshold :float
#  name                          :string           not null
#  next_response_time_threshold  :float
#  only_during_business_hours    :boolean          default(FALSE)
#  resolution_time_threshold     :float
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#
# Indexes
#
#  index_sla_policies_on_account_id  (account_id)
#
class SlaPolicy < ApplicationRecord
  belongs_to :account
  validates :name, presence: true

  has_many :conversations, dependent: :nullify
  has_many :applied_slas, dependent: :destroy_async

  def push_event_data
    {
      id: id,
      name: name,
      frt: first_response_time_threshold,
      nrt: next_response_time_threshold,
      rt: resolution_time_threshold
    }
  end

  # Safe accessor for the jsonb auto_apply config. Shape:
  # { 'enabled' => bool, 'event' => 'conversation_created', 'inbox_ids' => [Integer], 'pipeline_ids' => [Integer] }
  def auto_apply_config
    config = auto_apply.is_a?(Hash) ? auto_apply : {}
    {
      'enabled' => ActiveModel::Type::Boolean.new.cast(config['enabled']) || false,
      'event' => config['event'].presence || 'conversation_created',
      'inbox_ids' => Array(config['inbox_ids']).map(&:to_i),
      'pipeline_ids' => Array(config['pipeline_ids']).map(&:to_i)
    }
  end
end
