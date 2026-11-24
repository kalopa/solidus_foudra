# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

ENV["RAILS_ENV"] = "test"

require "solidus_dev_support/rspec/coverage"

# Create the dummy app if it's still missing.
dummy_env = "#{__dir__}/dummy/config/environment.rb"
system "bin/rake extension:test_app" unless File.exist? dummy_env
require dummy_env

# Factories and helpers from solidus_core.
require "solidus_dev_support/rspec/feature_helper"
require "webmock/rspec"

Dir["#{__dir__}/support/**/*.rb"].sort.each { |f| require f }

SolidusDevSupport::TestingSupport::Factories.load_for(SolidusFoudra::Engine)

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = false
end
