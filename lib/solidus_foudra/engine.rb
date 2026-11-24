# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "solidus_core"
require "solidus_support"

module SolidusFoudra
  class Engine < Rails::Engine
    include SolidusSupport::EngineExtensions

    # Its own namespace, not Spree's: the one route (the webhook) is
    # SolidusFoudra::WebhooksController, mounted by the host app at /foudra.
    isolate_namespace SolidusFoudra

    engine_name "solidus_foudra"

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
