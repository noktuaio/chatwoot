class Crm::FollowUps::ReminderDismisser
  METADATA_KEY = 'reminder_dismissed_by'.freeze

  def initialize(follow_up:, user:)
    @follow_up = follow_up
    @user = user
  end

  def perform
    dismissed_by = (@follow_up.metadata || {}).to_h.stringify_keys[METADATA_KEY] || {}
    dismissed_by = dismissed_by.merge(@user.id.to_s => Time.current.iso8601)

    @follow_up.update!(
      metadata: @follow_up.metadata.merge(METADATA_KEY => dismissed_by)
    )
    @follow_up
  end

  def self.dismissed_for?(follow_up:, user:)
    return false if follow_up.blank? || user.blank?

    follow_up.metadata.to_h.stringify_keys.dig(METADATA_KEY, user.id.to_s).present?
  end
end
