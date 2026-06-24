json.payload do
  json.partial! 'api/v1/accounts/crm/pipeline_inboxes/pipeline_inbox', pipeline_inbox: @pipeline_inbox
end
