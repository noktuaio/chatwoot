json.payload do
  json.partial! 'api/v1/accounts/crm/inbox_settings/inbox_setting', inbox_setting: @inbox_setting
end
