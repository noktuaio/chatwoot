class AddCategoryAndThumbnailToEmailCampaignTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaign_templates, :category, :string
    add_column :email_campaign_templates, :thumbnail_url, :string
  end
end
