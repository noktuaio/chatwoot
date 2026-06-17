json.payload do
  json.array! @stage_automations, partial: 'api/v1/accounts/crm/stage_automations/stage_automation', as: :stage_automation
end
json.meta do
  json.count @stage_automations_count
end
