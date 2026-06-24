json.id stage_automation.id
json.account_id stage_automation.account_id
json.pipeline_id stage_automation.pipeline_id
json.stage_id stage_automation.stage_id
json.name stage_automation.name
json.description stage_automation.description
json.trigger_event stage_automation.trigger_event
json.enabled stage_automation.enabled
json.position stage_automation.position
json.metadata stage_automation.metadata
json.created_by_id stage_automation.created_by_id
json.created_at stage_automation.created_at
json.updated_at stage_automation.updated_at
json.steps stage_automation.steps.ordered do |step|
  json.partial! 'api/v1/accounts/crm/stage_automation_steps/step', step: step
end
