class CreateAutonomiaIdentityLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :autonomia_account_links do |t|
      t.references :account, null: false, foreign_key: true
      t.string :identity_organization_id, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :autonomia_account_links, :identity_organization_id, unique: true, name: 'idx_autonomia_account_links_identity_org'

    create_table :autonomia_user_links do |t|
      t.references :user, null: false, foreign_key: true
      t.string :identity_user_id, null: false
      t.string :email, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :autonomia_user_links, :identity_user_id, unique: true
    add_index :autonomia_user_links, :email
  end
end
