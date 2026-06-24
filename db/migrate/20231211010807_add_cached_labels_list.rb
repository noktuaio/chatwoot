class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
    if defined?(ActsAsTaggableOn::Taggable::Cache)
      ActsAsTaggableOn::Taggable::Cache.included(Conversation)
    elsif Conversation.respond_to?(:initialize_tags_cache)
      Conversation.initialize_tags_cache
    end
  end
end
