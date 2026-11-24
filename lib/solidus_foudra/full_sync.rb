# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # The nightly pass: products, stock, shipments of sent orders not yet
  # shipped here (last 60 days), orders since send_orders_since that never
  # reached Foudra, and pruning de-duplication rows older than 30 days.
  # Each step is independent: one failing doesn't stop the others.
  class FullSync
    STEPS = %i[products stock shipments resend prune].freeze

    def initialize(client: Client.new)
      @client = client
    end

    # {step => :ok | error message}
    def call(steps = STEPS)
      steps.index_with do |step|
        send(step)
        :ok
      rescue => e
        SolidusFoudra.log(:error, "nightly #{step} failed: #{e.class}: #{e.message}")
        e.message
      end
    end

    def products
      ProductSync.new(client:).sync_all
    end

    def stock
      StockSync.new(client:).update_all
    end

    def shipments
      ShipmentSync.new(client:).sync_open_orders
    end

    def resend
      since = SolidusFoudra.config.send_orders_since
      return unless since

      orders = Spree::Order.complete.where(completed_at: since.., foudra_sales_order_id: nil)
        .where.not(state: "canceled")
      orders.find_each do |order|
        OrderSender.new(order, client:).send_order
      rescue Client::Unavailable
        raise
      rescue Client::Error => e
        SolidusFoudra.log(:error, "order #{order.number}: not sent: #{e.message}")
      end
    end

    def prune
      WebhookEvent.prune
    end

    private

    attr_reader :client
  end
end
