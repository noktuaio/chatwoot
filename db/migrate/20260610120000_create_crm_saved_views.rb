class CreateCrmSavedViews < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_saved_views do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :pipeline, foreign_key: { to_table: :crm_pipelines }
      t.string :name, null: false
      # visibility: private_view(0) own-only, team(1) shared with team, account(2) shared account-wide
      t.integer :visibility, null: false, default: 0
      # config jsonb: { columns, filters, sort, group_by, density }
      t.jsonb :config, null: false, default: {}
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :crm_saved_views, [:account_id, :pipeline_id], name: 'idx_crm_saved_views_account_pipeline'
    add_index :crm_saved_views, [:account_id, :user_id], name: 'idx_crm_saved_views_account_user'
    add_index :crm_saved_views, [:account_id, :visibility], name: 'idx_crm_saved_views_account_visibility'
  end
end
