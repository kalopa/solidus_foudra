# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # The nightly pass (see FullSync), for a job scheduler.
  class FullSyncJob < ApplicationJob
    def perform
      FullSync.new.call
    end
  end
end
