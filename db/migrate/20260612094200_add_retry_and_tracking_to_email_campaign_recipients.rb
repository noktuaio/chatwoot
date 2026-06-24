class AddRetryAndTrackingToEmailCampaignRecipients < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaign_recipients, :attempts, :integer, null: false, default: 0
    add_column :email_campaign_recipients, :last_event_at, :datetime

    # Hot SNS lookup: EventProcessor#find_recipient does find_by(ses_message_id:) on EVERY
    # verified Delivery/Bounce/Complaint notification. Index it so the webhook stays index-backed.
    add_index :email_campaign_recipients, :ses_message_id
  end
end
