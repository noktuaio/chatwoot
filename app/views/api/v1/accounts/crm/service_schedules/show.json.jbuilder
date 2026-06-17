json.payload do
  json.partial! 'api/v1/accounts/crm/service_schedules/service_schedule', service_schedule: @service_schedule
end
