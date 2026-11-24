# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Sends a completed order to Foudra as a sales order. order_finalized is
  # published inside the checkout's transaction, so this may run before
  # the order is committed: it waits (retries) until it is.
  class SendOrderJob < ApplicationJob
    class NotYetComplete < StandardError; end

    retry_on NotYetComplete, wait: 10.seconds, attempts: 10 do |job, _error|
      SolidusFoudra.log(:warn, "order #{job.arguments.first}: never completed; not sent")
    end

    def perform(order_id)
      order = Spree::Order.find_by(id: order_id)
      raise NotYetComplete unless order&.completed_at && order.complete?

      OrderSender.new(order).send_order
    end
  end
end
