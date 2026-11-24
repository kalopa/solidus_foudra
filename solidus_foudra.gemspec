# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require_relative "lib/solidus_foudra/version"

Gem::Specification.new do |spec|
  spec.name = "solidus_foudra"
  spec.version = SolidusFoudra::VERSION
  spec.authors = ["Kalopa Robotics Limited"]
  spec.email = "dtynan@kalopa.com"

  spec.summary = "Connects a Solidus shop to Foudra MRP: orders in, stock, products and shipping out."
  spec.description = <<~DESC
    Sends each completed Solidus order to Foudra MRP as a sales order on the shop's
    channel (and cancels it there when it is cancelled here), and keeps the shop's
    stock, products, prices and shipments in step with Foudra through its webhooks
    and a nightly full pass.
  DESC
  spec.homepage = "https://foudra.com/developers"
  spec.license = "Apache-2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kalopa/solidus_foudra"
  spec.metadata["changelog_uri"] = "https://github.com/kalopa/solidus_foudra/releases"
  spec.metadata["bug_tracker_uri"] = "https://github.com/kalopa/solidus_foudra/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.1", "< 4")

  files = Dir.chdir(__dir__) { `git ls-files -z`.split("\x0") }

  spec.files = files.grep_v(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "solidus_core", "~> 4.6"
  spec.add_dependency "solidus_support", ">= 0.12.0"

  spec.add_development_dependency "solidus_dev_support", "~> 2.12"
  spec.add_development_dependency "webmock", "~> 3.0"
end
