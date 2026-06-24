json.payload do
  json.partial! 'api/v1/accounts/crm/stage_automations/stage_automation', stage_automation: @stage_automation
end
