class CreateCampaignImportLabels < ActiveRecord::Migration[7.0]
  def change
    create_table :campaign_import_labels do |t|
      t.bigint :campaign_import_id, null: false
      t.bigint :label_id
      t.string :title, null: false
      t.integer :kind, default: 0, null: false
      t.integer :batch_index
      t.integer :planned_count, default: 0, null: false
      t.integer :applied_count, default: 0, null: false

      t.timestamps
    end

    add_index :campaign_import_labels, :campaign_import_id
    add_index :campaign_import_labels, :label_id
    add_index :campaign_import_labels, [:campaign_import_id, :title], unique: true, name: 'idx_campaign_import_labels_on_import_and_title'
  end
end
