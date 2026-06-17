class AddDirectInboxToEmailCampaigns < ActiveRecord::Migration[7.1]
  def up
    # Modo de envio: 0=ses (domínio verificado, padrão), 1=direct_inbox (envio direto pela caixa).
    add_column :email_campaigns, :delivery_mode, :integer, null: false, default: 0
    # Caixa que envia no modo direto (webmail conectado). Nulo no modo SES.
    add_reference :email_campaigns, :sender_inbox, null: true, foreign_key: { to_table: :inboxes }, index: true
    # sender_identity deixa de ser obrigatório (só existe no modo SES).
    change_column_null :email_campaigns, :sender_identity_id, true
  end

  def down
    change_column_null :email_campaigns, :sender_identity_id, false
    remove_reference :email_campaigns, :sender_inbox
    remove_column :email_campaigns, :delivery_mode
  end
end
