# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Spree::Bus events that send an order to Foudra or cancel it there. Only
  # the order's id goes on the queue; the job reloads it.
  class OrderSubscriber
    include Omnes::Subscriber

    handle :order_finalized, with: :send_order, id: :solidus_foudra_send_order
    handle :order_canceled, with: :cancel_order, id: :solidus_foudra_cancel_order

    def send_order(event)
      return unless SolidusFoudra.config.enabled?

      SendOrderJob.perform_later(event[:order].id)
    end

    def cancel_order(event)
      return unless SolidusFoudra.config.enabled?

      CancelOrderJob.perform_later(event[:order].id)
    end
  end
end
