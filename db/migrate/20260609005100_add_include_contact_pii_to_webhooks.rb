class AddIncludeContactPiiToWebhooks < ActiveRecord::Migration[7.1]
  # Additive, default-deny (plan B4/D4). CRM outbound webhooks exclude contact
  # PII (email/phone) by default; this opt-in flag lets an admin explicitly
  # include it on a per-webhook basis. Defaults false so existing rows and the
  # CE build keep the safe behavior.
  def change
    add_column :webhooks, :include_contact_pii, :boolean, default: false, null: false
  end
end
