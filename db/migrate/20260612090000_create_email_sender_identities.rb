class CreateEmailSenderIdentities < ActiveRecord::Migration[7.1]
  def change
    create_table :email_sender_identities do |t|
      t.references :account, null: false, foreign_key: true
      t.string :domain, null: false
      t.string :from_email
      t.bigint :reply_to_inbox_id
      # status: pending(0) verifying(1) verified(2) failed(3)
      t.integer :status, null: false, default: 0
      t.jsonb :dkim_records, null: false, default: []
      t.string :spf_record
      t.string :dmarc_record
      t.string :ses_configuration_set
      t.string :provider, null: false, default: 'ses'
      t.datetime :verified_at
      t.string :last_error

      t.timestamps
    end

    add_index :email_sender_identities,
              'account_id, lower(domain)',
              unique: true,
              name: 'idx_email_sender_identities_account_domain'
    add_index :email_sender_identities, [:account_id, :status],
              name: 'idx_email_sender_identities_account_status'
  end
end
