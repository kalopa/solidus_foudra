# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "bigdecimal"

module SolidusFoudra
  # A shipped Foudra shipment on this channel ships, in the Solidus order
  # whose number is its sales order's channel_order_ref, as many
  # not-yet-shipped units of each line's part as Foudra shipped: one carton
  # per Solidus shipment, external_number = the Foudra shipment's number,
  # tracking = its tracking number. Solidus then sends its shipped email.
  # A repeat finds the cartons by external_number, ships only what they
  # don't already hold and corrects the tracking (no second email).
  class ShipmentSync
    def initialize(client: Client.new)
      @client = client
    end

    def sync_id(shipment_id)
      sync(client.shipment(shipment_id))
    rescue Client::NotFound
      SolidusFoudra.log(:warn, "shipment #{shipment_id}: not found in Foudra")
    end

    # Shipments of orders sent to Foudra but not yet shipped here.
    def sync_open_orders(since: 60.days.ago)
      orders = Spree::Order.complete.where(completed_at: since..).where.not(foudra_sales_order_id: nil)
        .where.not(shipment_state: "shipped").where.not(state: "canceled")
      orders.find_each do |order|
        client.shipments_for(order.foudra_sales_order_id).each { |s| sync(client.shipment(s["id"]), order:) }
      rescue Client::Unavailable
        raise
      rescue Client::Error, ActiveRecord::ActiveRecordError => e
        SolidusFoudra.log(:error, "order #{order.number}: shipments not synced: #{e.message}")
      end
    end

    def sync(shipment, order: nil)
      return unless shipment["status"] == "shipped"

      sales_order = client.sales_order(shipment["sales_order_id"])
      return unless sales_order["channel"] == SolidusFoudra.config.channel

      order ||= Spree::Order.find_by(number: sales_order["channel_order_ref"])
      unless order
        return SolidusFoudra.log(:warn, "shipment #{shipment["number"]}: no order #{sales_order["channel_order_ref"]}")
      end

      Ship.new(order, shipment).call
    end

    private

    attr_reader :client

    class Ship
      def initialize(order, shipment)
        @order = order
        @shipment = shipment
        @number = shipment["number"].to_s
        @tracking = shipment["tracking_number"].presence
      end

      def call
        correct_tracking
        units = units_to_ship
        if units.empty?
          return SolidusFoudra.log(:info, "order #{order.number}: shipment #{number} already shipped here")
        end

        shipped_at = Time.zone.parse(shipment["shipped_at"].to_s) || Time.current
        units.group_by(&:shipment).each do |solidus_shipment, group|
          Spree::OrderShipping.new(order).ship(
            inventory_units: group,
            stock_location: solidus_shipment.stock_location,
            address: order.ship_address,
            shipping_method: solidus_shipment.shipping_method,
            shipped_at:,
            external_number: number,
            tracking_number: tracking
          )
        end
        SolidusFoudra.log(:info, "order #{order.number}: shipped #{units.size} unit(s) as #{number}")
      end

      private

      attr_reader :order, :shipment, :number, :tracking

      def cartons
        @cartons ||= Spree::Carton.joins(:inventory_units)
          .where(external_number: number, spree_inventory_units: {shipment_id: order.shipments.select(:id)}).distinct.to_a
      end

      def correct_tracking
        cartons.each do |carton|
          next if carton.tracking == tracking

          carton.update!(tracking:)
          carton.shipments.each { |s| s.update!(tracking:) }
        end
      end

      # Per part: what Foudra shipped, less what this shipment's cartons
      # already hold, taken from the order's on-hand units. Backordered
      # units wait for the stock update.
      def units_to_ship
        in_cartons = cartons.flat_map(&:inventory_units).group_by(&:variant_id).transform_values(&:size)
        wanted = Hash.new(0)
        Array(shipment["lines"]).each do |line|
          wanted[line["part_number"].to_s] += BigDecimal(line["quantity"].to_s).floor
        end

        units = order.inventory_units.includes(:variant, :shipment).to_a
        wanted.flat_map do |part_number, quantity|
          mine = units.select { |u| PartNumbers.of(u.variant) == part_number }
          already = mine.map(&:variant_id).uniq.sum { |id| in_cartons.fetch(id, 0) }
          open = mine.select(&:on_hand?)
          open.first([quantity - already, 0].max)
        end
      end
    end
  end
end
