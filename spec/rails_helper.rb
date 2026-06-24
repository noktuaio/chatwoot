ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../config/environment', __dir__)
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'
require 'active_job/test_helper'

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |file| require file }

RSpec.configure do |config|
  config.fixture_path = Rails.root.join('spec/fixtures').to_s
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.include ActiveJob::TestHelper

  config.before do
    ActiveJob::Base.queue_adapter = :test
    ActiveStorage::Current.url_options = { host: 'www.example.com' }
  end
end
