json.payload do
  json.array! @pipeline_inboxes do |pipeline_inbox|
    json.partial! 'api/v1/accounts/crm/pipeline_inboxes/pipeline_inbox', pipeline_inbox: pipeline_inbox
  end
end

json.meta do
  json.count @pipeline_inboxes_count
end
