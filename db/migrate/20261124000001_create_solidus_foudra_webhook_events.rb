# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

# One row per Foudra webhook event received, so a redelivery is dropped.
# The nightly pass prunes rows older than 30 days.
class CreateSolidusFoudraWebhookEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :solidus_foudra_webhook_events do |t|
      t.string :event_id, null: false
      t.string :event_type
      t.datetime :created_at, null: false
    end
    add_index :solidus_foudra_webhook_events, :event_id, unique: true
    add_index :solidus_foudra_webhook_events, :created_at
  end
end
