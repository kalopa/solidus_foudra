# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "bigdecimal"

module SolidusFoudra
  # Sets each variant's count on hand, at the configured stock location, to
  # Foudra's available quantity for its part: on hand less what open orders
  # commit, rounded down, never below zero. Variants that don't track
  # inventory are left alone.
  class StockSync
    def initialize(client: Client.new)
      @client = client
    end

    # Re-fetches each part by id and sets its stock.
    def update_parts(part_ids)
      Array(part_ids).uniq.each do |id|
        update(client.part(id))
      rescue Client::NotFound
        SolidusFoudra.log(:warn, "part #{id}: not found in Foudra")
      end
    end

    # Every part, 100 a page. Returns how many variants changed.
    def update_all
      client.parts.sum { |part| update(part) }
    end

    # Sets the stock of the variants with this part's number. Returns how
    # many changed.
    def update(part)
      number = part["part_number"].to_s
      return 0 if number.empty?

      count = self.class.available(part["available"])
      PartNumbers.variants(number).sum do |variant|
        next 0 unless variant.should_track_inventory?

        item = location.stock_item_or_create(variant)
        next 0 if item.count_on_hand == count

        item.set_count_on_hand(count)
        SolidusFoudra.log(:info, "#{number}: count on hand #{count}")
        1
      end
    end

    def self.available(value)
      [BigDecimal(value.presence || "0").floor, 0].max
    rescue ArgumentError
      0
    end

    private

    attr_reader :client

    def location
      @location ||= SolidusFoudra.config.stock_location_record
    end
  end
end
