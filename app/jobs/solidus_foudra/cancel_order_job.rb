# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Cancels in Foudra what hasn't shipped of a cancelled order.
  class CancelOrderJob < ApplicationJob
    def perform(order_id)
      order = Spree::Order.find_by(id: order_id)
      OrderSender.new(order).cancel_order if order
    end
  end
end
