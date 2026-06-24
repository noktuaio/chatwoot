class CreateAccountEmailOauthApps < ActiveRecord::Migration[7.1]
  def change
    create_table :account_email_oauth_apps do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :provider, null: false
      t.text :client_id
      t.text :client_secret
      t.string :redirect_uri
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :account_email_oauth_apps, %i[account_id provider], unique: true
  end
end
