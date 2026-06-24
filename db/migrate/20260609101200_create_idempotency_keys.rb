class CreateIdempotencyKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :idempotency_keys do |t|
      t.references :account, null: false, foreign_key: true
      t.string :key, null: false
      # sha256 of method+path+body — lets us reject a reused key on a different request.
      t.string :request_fingerprint, null: false
      t.integer :response_status
      t.jsonb :response_body
      # 0 = processing (claimed, action in flight), 1 = done (2xx response stored).
      t.integer :state, null: false, default: 0

      t.datetime :created_at, null: false
    end

    # Claim-first idempotency (B-API2): unique [account_id, key] lets the claim
    # INSERT lose atomically on a concurrent duplicate (ON CONFLICT DO NOTHING).
    add_index :idempotency_keys, %i[account_id key], unique: true, name: 'uniq_idempotency_keys_per_account'
    # Supports the 24h TTL cleanup sweep.
    add_index :idempotency_keys, :created_at, name: 'idx_idempotency_keys_created_at'
  end
end
