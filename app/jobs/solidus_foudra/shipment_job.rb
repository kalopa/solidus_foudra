# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Re-fetches a shipment and its sales order and ships the Solidus units
  # (or corrects the tracking).
  class ShipmentJob < ApplicationJob
    def perform(shipment_id)
      ShipmentSync.new.sync_id(shipment_id)
    end
  end
end
