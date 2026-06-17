module Crm
  class Config
    BOOLEAN = ActiveModel::Type::Boolean.new

    def self.enabled?
      BOOLEAN.cast(ENV.fetch('CRM_KANBAN_ENABLED', false))
    end
  end
end
