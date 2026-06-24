json.payload do
  json.partial! 'api/v1/accounts/crm/stages/stage', stage: @stage
end
