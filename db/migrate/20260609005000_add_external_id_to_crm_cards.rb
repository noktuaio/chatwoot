class AddExternalIdToCrmCards < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_cards, :external_id, :string

    # Partial unique index: at most one card per (account, external_id) when set.
    # Mirrors contacts' uniq_identifier_per_account_contact. Enables idempotent
    # upserts from external systems (n8n) without duplicating on retries.
    add_index :crm_cards, %i[account_id external_id],
              unique: true,
              where: 'external_id IS NOT NULL',
              name: 'uniq_crm_cards_external_id_per_account'
  end
end
