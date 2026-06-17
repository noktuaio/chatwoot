json.payload do
  json.array! @inbox_settings do |inbox_setting|
    json.partial! 'api/v1/accounts/crm/inbox_settings/inbox_setting', inbox_setting: inbox_setting
  end
end

json.meta do
  json.count @inbox_settings_count
end
