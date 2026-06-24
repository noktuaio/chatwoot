class AddIntegrationToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    # Marks the hidden AccountUser backing a Crm::IntegrationToken. Account#agents
    # filters integration:false so these NEVER leak into agent pickers /
    # assignment / round-robin / reports / @mentions (plan B-T4).
    add_column :account_users, :integration, :boolean, null: false, default: false
    add_index :account_users, :integration
  end
end
