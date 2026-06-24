# V2.1 — agent "actuation": external (atende clientes) / internal (copiloto da equipe) / both.
# Additive + default 0 (external) so every existing agent keeps behaving exactly as today.
class AddActuationToAutonomiaAgents < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    unless column_exists?(:autonomia_agents, :actuation)
      add_column :autonomia_agents, :actuation, :integer, null: false, default: 0
    end

    unless index_exists?(:autonomia_agents, %i[account_id actuation],
                         name: 'idx_autonomia_agents_account_actuation')
      add_index :autonomia_agents, %i[account_id actuation],
                name: 'idx_autonomia_agents_account_actuation', algorithm: :concurrently
    end
  end

  def down
    if index_exists?(:autonomia_agents, %i[account_id actuation],
                     name: 'idx_autonomia_agents_account_actuation')
      remove_index :autonomia_agents, name: 'idx_autonomia_agents_account_actuation',
                                      algorithm: :concurrently
    end
    remove_column :autonomia_agents, :actuation if column_exists?(:autonomia_agents, :actuation)
  end
end
