json.payload do
  json.array! @saved_views, partial: 'saved_view', as: :saved_view
end
