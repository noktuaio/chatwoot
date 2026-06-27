ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../config/environment', __dir__)
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'
require 'active_job/test_helper'
# Pundit's `permissions` matcher (policy specs) and test-prof's `let_it_be`
# (builder specs) are used by specs but were never required, so those specs
# failed to load and aborted their CI shard. Both gems are already bundled.
require 'pundit/rspec'
require 'test_prof/recipes/rspec/let_it_be'

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
