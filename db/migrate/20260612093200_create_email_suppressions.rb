class CreateEmailSuppressions < ActiveRecord::Migration[7.1]
  def change
    create_table :email_suppressions do |t|
      t.references :account, null: false, foreign_key: true
      t.string :email, null: false
      t.string :reason   # hard_bounce / complaint / unsubscribe / manual
      t.string :source   # ses / api / import / manual
      t.datetime :created_at, null: false
    end

    add_index :email_suppressions,
              'account_id, lower(email)',
              unique: true,
              name: 'idx_email_suppressions_account_email'
  end
end
