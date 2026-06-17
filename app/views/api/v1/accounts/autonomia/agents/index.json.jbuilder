json.payload do
  json.array! @agents, partial: 'api/v1/accounts/autonomia/agents/agent', as: :agent
end

# The FE store factory's SET_META mutation reads meta.total_count/meta.page on
# every list load; without a meta block it throws and the Hub shows a load error.
json.meta do
  json.total_count @agents.size
  json.page 1
end
