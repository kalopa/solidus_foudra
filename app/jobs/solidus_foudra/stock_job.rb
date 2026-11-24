# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Re-fetches these parts and sets their stock.
  class StockJob < ApplicationJob
    def perform(part_ids)
      StockSync.new.update_parts(part_ids)
    end
  end
end
