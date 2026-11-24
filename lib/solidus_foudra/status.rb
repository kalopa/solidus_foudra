# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # What bin/rails solidus_foudra:status prints: the configuration (never
  # the secrets) and whether Foudra agrees with it.
  class Status
    def initialize(config = SolidusFoudra.config, client: Client.new(config), out: $stdout)
      @config = config
      @client = client
      @out = out
    end

    # true when everything checked out.
    def call
      ok = true
      line "base_url", config.base_url.presence || "(not set)"
      line "channel", config.channel.presence || "(not set)"
      line "api_key", config.api_key.present? ? "set" : "(not set)"
      line "webhook_secret", config.webhook_secret.present? ? "set" : "(not set: webhooks will be refused)"
      line "part_number_column", config.part_number_column
      line "sync_content", config.sync_content.inspect
      line "send_orders_since", config.send_orders_since.inspect
      ok &= check("spree_variants.#{config.part_number_column}") do
        raise "no such column" unless Spree::Variant.column_names.include?(config.part_number_column)

        "#{Spree::Variant.where.not(config.part_number_column => [nil, ""]).count} variant(s) with a part number"
      end
      ok &= check("stock location") { config.stock_location_record.name }
      return fail_with("not configured: base_url, api_key and channel are needed") unless config.enabled?

      ok &= check("channel #{config.channel}") do
        channel = client.channels.find { |c| c["code"] == config.channel }
        raise "Foudra has no channel #{config.channel}" unless channel
        raise "channel #{config.channel} is not active" if channel["is_active"] == false

        channel["name"]
      end
      ok &= check("listings") do
        listings = client.listings
        listed = listings.select { |l| l["is_listed"] }
        unpriced = listed.count { |l| l["price"].blank? }
        "#{listed.size} listed of #{listings.size}, #{unpriced} without a price"
      end
      ok
    end

    private

    attr_reader :config, :client, :out

    def line(label, value)
      out.puts format("%-20s %s", label, value)
    end

    def check(label)
      line label, "ok: #{yield}"
      true
    rescue => e
      line label, "FAILED: #{Redact.call(e.message)}"
      false
    end

    def fail_with(message)
      out.puts message
      false
    end
  end
end
