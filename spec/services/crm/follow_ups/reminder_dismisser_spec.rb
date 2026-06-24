require 'rails_helper'

RSpec.describe Crm::FollowUps::ReminderDismisser do
  it 'records reminder dismissal per user without changing follow-up status' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead')
    follow_up = account.crm_follow_ups.create!(
      card: card,
      title: 'Retornar',
      due_at: 10.minutes.ago,
      timezone: 'UTC',
      automation_mode: :reminder_only,
      status: :overdue,
      created_by: admin
    )

    described_class.new(follow_up: follow_up, user: admin).perform

    expect(follow_up.reload.status).to eq('overdue')
    expect(described_class.dismissed_for?(follow_up: follow_up, user: admin)).to be(true)
  end
end
