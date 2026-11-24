# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Re-fetches a part's listing on the channel and creates, updates or
  # discontinues its product.
  class ListingJob < ApplicationJob
    def perform(part_id)
      ProductSync.new.sync_part(part_id)
    end
  end
end
