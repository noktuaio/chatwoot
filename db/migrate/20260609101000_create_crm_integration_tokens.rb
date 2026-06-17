class CreateCrmIntegrationTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_integration_tokens do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      # One managed CustomRole + one hidden AccountUser per token (plan §3.2).
      # nullify (not cascade) on those FKs so an in-flight auth request can still
      # fail-closed (status check / blank custom_role => DENY) rather than 500.
      t.references :custom_role, foreign_key: { to_table: :custom_roles, on_delete: :nullify }
      t.references :account_user, foreign_key: { to_table: :account_users, on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :last_used_at
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
