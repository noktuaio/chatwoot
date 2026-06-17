require 'rails_helper'
require 'yaml'

RSpec.describe 'CRM scheduled jobs' do # rubocop:disable RSpec/DescribeClass
  it 'schedules the follow-up due job through sidekiq-cron' do
    schedule = YAML.safe_load_file(Rails.root.join('config/schedule.yml'), aliases: true)

    expect(schedule['crm_follow_up_due_job']).to include(
      'class' => 'Crm::FollowUpDueJob',
      'queue' => 'scheduled_jobs'
    )
    expect(schedule['crm_follow_up_due_job']['cron']).to eq('*/1 * * * *')
  end
end
