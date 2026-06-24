class AddEventCountersToEmailCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaigns, :delivered_count, :integer, null: false, default: 0
    add_column :email_campaigns, :opened_count, :integer, null: false, default: 0
    add_column :email_campaigns, :clicked_count, :integer, null: false, default: 0
    add_column :email_campaigns, :bounced_count, :integer, null: false, default: 0
    add_column :email_campaigns, :complained_count, :integer, null: false, default: 0
    add_column :email_campaigns, :unsubscribed_count, :integer, null: false, default: 0
  end
end
