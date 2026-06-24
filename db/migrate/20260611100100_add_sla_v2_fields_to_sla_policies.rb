class AddSlaV2FieldsToSlaPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :sla_policies, :exclude_groups, :boolean, null: false, default: true
    add_column :sla_policies, :ai_skip_natural_pause, :boolean, null: false, default: true
    add_column :sla_policies, :auto_apply, :jsonb, null: false, default: {}
  end
end
