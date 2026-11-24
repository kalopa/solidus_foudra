# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

namespace :solidus_foudra do
  desc "Show the Foudra configuration (not the secrets) and check the channel and listings"
  task status: :environment do
    exit(1) unless SolidusFoudra::Status.new.call
  end

  desc "First import: products for every listing on the channel, then stock"
  task import: :environment do
    results = SolidusFoudra::FullSync.new.call(%i[products stock])
    results.each { |step, result| puts "#{step}: #{result}" }
    exit(1) unless results.values.all?(:ok)
  end

  desc "The nightly pass: products, stock, shipments, missed orders, pruning"
  task sync: :environment do
    results = SolidusFoudra::FullSync.new.call
    results.each { |step, result| puts "#{step}: #{result}" }
    exit(1) unless results.values.all?(:ok)
  end
end
