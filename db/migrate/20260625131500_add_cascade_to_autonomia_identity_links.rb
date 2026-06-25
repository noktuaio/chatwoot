# frozen_string_literal: true

class AddCascadeToAutonomiaIdentityLinks < ActiveRecord::Migration[7.1]
  def up
    replace_foreign_key(:autonomia_account_links, :accounts, :account_id, on_delete: :cascade)
    replace_foreign_key(:autonomia_user_links, :users, :user_id, on_delete: :cascade)

    return unless column_exists?(:autonomia_user_links, :account_id)

    replace_foreign_key(:autonomia_user_links, :accounts, :account_id, on_delete: :cascade)
  end

  def down
    replace_foreign_key(:autonomia_account_links, :accounts, :account_id)
    replace_foreign_key(:autonomia_user_links, :users, :user_id)

    return unless column_exists?(:autonomia_user_links, :account_id)

    replace_foreign_key(:autonomia_user_links, :accounts, :account_id)
  end

  private

  def replace_foreign_key(from_table, to_table, column, options = {})
    return unless table_exists?(from_table) && table_exists?(to_table) && column_exists?(from_table, column)

    remove_foreign_key(from_table, column: column) if foreign_key_exists?(from_table, column: column)
    add_foreign_key(from_table, to_table, column: column, **options)
  end
end
