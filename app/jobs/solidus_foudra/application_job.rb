# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Foudra busy or down (429, 5xx, network) after the client's own three
  # attempts: retried with growing pauses (executions**4 seconds: 3s, 18s,
  # 83s, … about two and a half hours in all). A refusal (401/402/403, 422,
  # an unknown part number) is logged and dropped: retrying won't fix it.
  class ApplicationJob < ActiveJob::Base
    queue_as { SolidusFoudra.config.queue }

    # Handlers declared later win, so the general refusal comes first and
    # the retry for Unavailable (a kind of Client::Error) after it.
    rescue_from Client::Error do |error|
      SolidusFoudra.log(:error, "#{self.class.name} dropped: #{error.message}")
    end

    retry_on Client::Unavailable, attempts: 9, wait: ->(executions) { (executions**4) + 2 } do |job, error|
      SolidusFoudra.log(:error, "#{job.class.name} gave up: #{error.message}")
    end

    discard_on ActiveJob::DeserializationError

    around_perform do |_job, block|
      block.call if SolidusFoudra.config.enabled?
    end
  end
end
