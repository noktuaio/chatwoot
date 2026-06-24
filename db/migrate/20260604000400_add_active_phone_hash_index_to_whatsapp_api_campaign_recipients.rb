class AddActivePhoneHashIndexToWhatsappApiCampaignRecipients < ActiveRecord::Migration[7.0]
  def change
    add_index :whatsapp_api_campaign_recipients,
              [:whatsapp_api_campaign_id, :phone_hash],
              unique: true,
              where: 'phone_hash IS NOT NULL AND status IN (0, 1, 2)',
              name: 'idx_wa_api_recipients_active_phone_hash'
  end
end
