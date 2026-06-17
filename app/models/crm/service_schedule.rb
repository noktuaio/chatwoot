class Crm::ServiceSchedule < ApplicationRecord
  self.table_name = 'crm_service_schedules'

  OWNER_TYPES = %w[Inbox User].freeze

  belongs_to :account
  belongs_to :owner, polymorphic: true

  validates :timezone, presence: true
  validates :owner_type, inclusion: { in: OWNER_TYPES }
  validates :owner_id, uniqueness: { scope: [:account_id, :owner_type] }
  validate :timezone_must_be_valid
  validate :blocks_must_be_well_formed

  scope :enabled, -> { where(enabled: true) }

  def usable?
    enabled? && parsed_blocks.any?
  end

  # Sorted, coalesced [start_minute, end_minute] pairs for a weekday (0=Sunday..6=Saturday).
  # Overlapping/duplicate blocks are merged so business-time math never double-counts.
  def blocks_for(wday)
    intervals = parsed_blocks.select { |block| block['day_of_week'] == wday }
                             .map { |block| [block['start_minute'], block['end_minute']] }
                             .sort_by(&:first)
    intervals.each_with_object([]) do |(start_minute, end_minute), merged|
      if merged.any? && start_minute <= merged.last[1]
        merged.last[1] = [merged.last[1], end_minute].max
      else
        merged << [start_minute, end_minute]
      end
    end
  end

  private

  def parsed_blocks
    blocks.is_a?(Array) ? blocks : []
  end

  def timezone_must_be_valid
    TZInfo::Timezone.get(timezone.to_s)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:timezone, 'is not a valid IANA timezone identifier')
  end

  def blocks_must_be_well_formed
    return errors.add(:blocks, 'must be an array') unless blocks.is_a?(Array)

    valid = blocks.all? do |block|
      block.is_a?(Hash) &&
        (0..6).cover?(block['day_of_week']) &&
        block['start_minute'].is_a?(Integer) && (0..1438).cover?(block['start_minute']) &&
        block['end_minute'].is_a?(Integer) && block['end_minute'] > block['start_minute'] && block['end_minute'] <= 1440
    end
    errors.add(:blocks, 'contains an invalid block') unless valid
  end
end
