# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.
#
# SolidusFoudra connects a Solidus shop to Foudra MRP. Orders go in to
# Foudra as sales orders; stock, products, prices and shipments come back
# out. Foudra owns the physical facts (what, how many, where, shipped);
# Solidus owns the shop, the checkout and the money. See README.md.

require "solidus_foudra/version"
require "solidus_foudra/configuration"
require "solidus_foudra/redact"
require "solidus_foudra/client"
require "solidus_foudra/webhook_signature"
require "solidus_foudra/markdown"
require "solidus_foudra/part_numbers"
require "solidus_foudra/customer_finder"
require "solidus_foudra/order_sender"
require "solidus_foudra/stock_sync"
require "solidus_foudra/product_sync"
require "solidus_foudra/shipment_sync"
require "solidus_foudra/full_sync"
require "solidus_foudra/status"
require "solidus_foudra/engine"

module SolidusFoudra
  class << self
    def configuration
      @configuration ||= Configuration.new
    end
    alias_method :config, :configuration

    def configure
      yield configuration
    end

    # For tests: forget the configuration.
    def reset_configuration!
      @configuration = Configuration.new
    end

    def logger
      configuration.logger || Rails.logger
    end

    # Every line this gem logs goes through here, so it is tagged and so
    # there is one place that never lets an email address through.
    def log(level, message)
      logger.public_send(level, "[solidus_foudra] #{Redact.call(message)}")
    end
  end
end
