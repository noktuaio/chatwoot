class AddMetadataToAppliedSlas < ActiveRecord::Migration[7.1]
  def change
    add_column :applied_slas, :metadata, :jsonb, null: false, default: {}
  end
end
