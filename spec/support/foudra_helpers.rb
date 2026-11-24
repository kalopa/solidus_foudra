# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

# A configured gem talking to a stubbed Foudra at acme.foudra.com, jobs
# queued (not run) unless a spec runs them, and the log captured so specs
# can prove what it doesn't say.
module FoudraHelpers
  BASE = "https://acme.foudra.com"
  API_KEY = "fdr_#{"k" * 64}"
  SECRET = "whsec-test-secret"

  def foudra_url(path)
    "#{BASE}#{path}"
  end

  # Stubs one Foudra request answering JSON.
  def stub_foudra(method, path, body: nil, status: 200, query: nil)
    stub = stub_request(method, foudra_url(path))
    stub = stub.with(query:) if query
    stub.to_return(status:, body: body.nil? ? "" : JSON.generate(body),
      headers: {"Content-Type" => "application/json"})
  end

  def log_output
    @log_io.string
  end

  def signed_headers(body, secret: SECRET, now: Time.now)
    {"X-Foudra-Signature" => SolidusFoudra::WebhookSignature.header_for(secret, body, now:),
     "Content-Type" => "application/json"}
  end
end

RSpec.configure do |config|
  config.include FoudraHelpers
  config.include ActiveJob::TestHelper

  config.before do
    SolidusFoudra.reset_configuration!
    @log_io = StringIO.new
    SolidusFoudra.configure do |c|
      c.base_url = FoudraHelpers::BASE
      c.api_key = FoudraHelpers::API_KEY
      c.webhook_secret = FoudraHelpers::SECRET
      c.channel = "SHOP"
      c.logger = Logger.new(@log_io)
    end
    ActiveJob::Base.queue_adapter = :test
    # No real pauses between retries.
    allow_any_instance_of(SolidusFoudra::Client).to receive(:sleep)
  end

  # The log must never carry the API key, in any spec.
  config.after do
    expect(@log_io.string).not_to include(FoudraHelpers::API_KEY)
  end
end
