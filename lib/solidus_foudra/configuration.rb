# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # The settings, from config/initializers/solidus_foudra.rb. The API key
  # and the webhook secret come from ENV or Rails credentials and are never
  # committed; #inspect leaves them out so a stray `p config` can't leak them.
  class Configuration
    # https://<company>.foudra.com: the company's own subdomain, where its
    # API key works and nowhere else.
    attr_accessor :base_url
    # fdr_…: an API key with the write scope (orders and customers are writes).
    attr_accessor :api_key
    # The signing secret Foudra showed once when the webhook was made.
    attr_accessor :webhook_secret
    # The code of the Foudra channel that is this shop, e.g. "SHOP".
    attr_accessor :channel
    # Where Foudra's available stock is put: a Spree::StockLocation, its id,
    # its name, or nil for the default (or only) one.
    attr_accessor :stock_location
    # The spree_variants column holding the Foudra part number. The install
    # migration adds foudra_part_number; Kalopa's shop uses :stock_code.
    attr_writer :part_number_column
    # false: a product's name, description and image are Foudra's only when
    # the product is created here; afterwards the shop edits them. true:
    # every sync overwrites them from Foudra.
    attr_accessor :sync_content
    # How old a webhook's signed timestamp may be, in seconds.
    attr_accessor :webhook_tolerance
    # The nightly pass re-sends orders completed since this time that never
    # reached Foudra (a job that gave up). nil: it doesn't. Set it to when
    # the gem went live: an older order, already shipped by other means,
    # would become demand in Foudra again.
    attr_accessor :send_orders_since
    # Days after the order date that a sales order is wanted.
    attr_accessor :wanted_after_days
    attr_accessor :open_timeout, :read_timeout
    # Attempts per request inside one job, on 429 and 5xx; ActiveJob's own
    # retries, with longer pauses, come after.
    attr_accessor :max_attempts
    # The ActiveJob queue for this gem's jobs.
    attr_accessor :queue
    # Logger; Rails.logger when nil.
    attr_accessor :logger
    # A callable turning Markdown into HTML, if the shop has a Markdown gem
    # it prefers; nil uses SolidusFoudra::Markdown.
    attr_accessor :markdown_renderer

    def initialize
      @part_number_column = :foudra_part_number
      @sync_content = false
      @webhook_tolerance = 300
      @wanted_after_days = 0
      @open_timeout = 10
      @read_timeout = 60
      @max_attempts = 3
      @queue = :default
    end

    # Nothing is sent or synced until the three essentials are set, so the
    # gem can be installed (and the test suite run) without a Foudra.
    def enabled?
      [base_url, api_key, channel].all?(&:present?)
    end

    def part_number_column
      @part_number_column.to_s
    end

    def stock_location_record
      case stock_location
      when Spree::StockLocation then stock_location
      when Integer then Spree::StockLocation.find(stock_location)
      when String, Symbol then Spree::StockLocation.find_by!(name: stock_location.to_s)
      else
        Spree::StockLocation.find_by(default: true) || Spree::StockLocation.order(:id).first!
      end
    end

    def inspect
      "#<#{self.class.name} base_url=#{base_url.inspect} channel=#{channel.inspect} " \
        "part_number_column=#{part_number_column.inspect} sync_content=#{sync_content.inspect}>"
    end
  end
end
