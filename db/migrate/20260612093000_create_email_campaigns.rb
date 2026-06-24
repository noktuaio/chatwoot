class CreateEmailCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :email_campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.references :sender_identity, null: false,
                   foreign_key: { to_table: :email_sender_identities }
      t.string :name, null: false
      t.string :subject, null: false
      t.string :from_name
      t.text :body_html
      t.string :reply_to
      # status: draft(0) scheduled(1) sending(2) sent(3) paused(4) canceled(5) failed(6)
      t.integer :status, null: false, default: 0
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.integer :recipients_count, null: false, default: 0
      t.integer :sent_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :suppressed_count, null: false, default: 0
      t.string :ses_configuration_set
      t.text :last_error

      t.timestamps
    end

    add_index :email_campaigns, [:account_id, :status, :scheduled_at],
              name: 'idx_email_campaigns_account_status_scheduled'
  end
end
