if ActiveModel::Type::Boolean.new.cast(ENV.fetch('WHATSAPP_API_CAMPAIGNS_ENABLED', false))
  ActiveJob::Base.log_arguments = false
end
