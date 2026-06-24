# Per-agent booking links. A profile in `per_agent` mode produces one of these per
# eligible agent: an opaque slug (SecureRandom.uuid) that, server-side, resolves to
# {agent, the agent's chosen calendar mailbox}. The agent shares THEIR link; a
# booking made through it is attributed to that agent (card owner + meeting host)
# and uses that agent's mailbox + availability. Additive — nothing references this
# table until the per_agent UI/flow is enabled.
class CreateCrmAgentBookingLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_agent_booking_links do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :booking_profile, null: false,
                                     foreign_key: { to_table: :crm_agent_booking_profiles }, index: true
      t.references :agent, null: false, foreign_key: { to_table: :users }, index: true
      t.references :inbox, null: false, foreign_key: true, index: true
      t.string :slug, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :crm_agent_booking_links, :slug, unique: true
    add_index :crm_agent_booking_links, [:booking_profile_id, :agent_id], unique: true,
                                        name: 'idx_crm_booking_links_profile_agent'
  end
end
