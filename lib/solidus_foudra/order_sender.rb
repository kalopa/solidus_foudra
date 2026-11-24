# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Sends a completed Solidus order to Foudra as a sales order on the
  # shop's channel, and cancels it there.
  class OrderSender
    def initialize(order, client: Client.new)
      @order = order
      @client = client
    end

    # The Foudra sales order's id, or nil when the order has nothing Foudra
    # makes (no line's variant has a part number).
    def send_order
      return order.foudra_sales_order_id if order.foudra_sales_order_id.present?

      lines = sales_order_lines
      if lines.empty?
        SolidusFoudra.log(:info, "order #{order.number}: no line has a part number; not sent")
        return
      end

      customer_id = order.foudra_customer_id.presence || CustomerFinder.new(order, client:).call
      sales_order = client.create_sales_order(body(customer_id, lines),
        idempotency_key: "solidus_foudra:order:#{order.number}")
      order.update_columns(foudra_customer_id: customer_id, foudra_sales_order_id: sales_order["id"])
      SolidusFoudra.log(:info, "order #{order.number}: Foudra sales order #{sales_order["number"]}")
      sales_order["id"]
    end

    # Foudra cancels what hasn't shipped; an order that has all shipped is
    # left (409, logged), as is one already cancelled there.
    def cancel_order
      id = order.foudra_sales_order_id.presence || client.find_sales_order(order.number)&.fetch("id")
      unless id
        SolidusFoudra.log(:info, "order #{order.number}: never reached Foudra; nothing to cancel")
        return
      end

      client.cancel_sales_order(id, idempotency_key: "solidus_foudra:cancel:#{order.number}")
      SolidusFoudra.log(:info, "order #{order.number}: cancelled in Foudra")
    rescue Client::Conflict => e
      SolidusFoudra.log(:warn, "order #{order.number}: not cancelled in Foudra: #{e.message}")
    end

    private

    attr_reader :order, :client

    def body(customer_id, lines)
      ordered = order.completed_at.to_date
      {
        channel: SolidusFoudra.config.channel,
        channel_order_ref: order.number,
        customer_id:,
        customer_reference: order.number,
        ordered_at: ordered.iso8601,
        wanted_at: (ordered + SolidusFoudra.config.wanted_after_days.to_i).iso8601,
        currency: order.currency,
        ship_to: AddressFormat.call(order.ship_address, with_name: true),
        lines:
      }.compact
    end

    # What the customer was charged per unit, before order-level promotions
    # (line-level ones are in it). Information only: Foudra books no money.
    def sales_order_lines
      order.line_items.includes(:variant).filter_map do |item|
        part_number = PartNumbers.of(item.variant)
        next unless part_number

        unit = (item.total_before_tax / item.quantity).round(4)
        {part_number:, quantity: item.quantity.to_s, unit_price: unit.to_s("F")}
      end
    end
  end
end
