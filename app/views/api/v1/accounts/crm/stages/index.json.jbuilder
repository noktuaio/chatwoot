json.payload do
  json.array! @stages do |stage|
    json.partial! 'api/v1/accounts/crm/stages/stage', stage: stage
  end
end

json.meta do
  json.count @stages_count
end
