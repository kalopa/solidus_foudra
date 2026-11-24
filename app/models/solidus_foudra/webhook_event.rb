# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # A Foudra webhook event already received: its id is unique, so recording
  # a redelivered event fails and the event is dropped.
  class WebhookEvent < ActiveRecord::Base
    self.table_name = "solidus_foudra_webhook_events"

    # true the first time an id is seen, false on a repeat.
    def self.record(event_id, event_type)
      create!(event_id: event_id.to_s, event_type: event_type.to_s, created_at: Time.current)
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def self.prune(older_than: 30.days)
      where(created_at: ...older_than.ago).delete_all
    end
  end
end
