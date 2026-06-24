class AddBuilderFieldsToEmailCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaigns, :body_mjml, :text
    add_column :email_campaigns, :preheader, :string
    add_column :email_campaigns, :from_email, :string
  end
end
