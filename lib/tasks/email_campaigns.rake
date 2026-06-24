namespace :email_campaigns do
  desc 'Ensure SES configuration-set event destination -> SNS topic -> webhook subscription'
  task ensure_event_destination: :environment do
    abort 'EMAIL_CAMPAIGN_ENABLED is off' unless EmailCampaigns::Config.enabled?

    arn = EmailCampaigns::Ses::EventDestinationEnsurer.new.perform
    puts "Event destination ensured. SNS topic: #{arn}"
  end
end
