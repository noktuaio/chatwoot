json.payload do
  json.partial! 'api/v1/accounts/crm/stage_automation_steps/step', step: @step
end
