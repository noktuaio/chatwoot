json.payload do
  json.array! @service_schedules do |service_schedule|
    json.partial! 'api/v1/accounts/crm/service_schedules/service_schedule', service_schedule: service_schedule
  end
end
