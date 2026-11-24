# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

SolidusFoudra::Engine.routes.draw do
  post "webhooks", to: "webhooks#create", as: :webhooks
end
