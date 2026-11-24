# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "openssl"

module SolidusFoudra
  # Checks X-Foudra-Signature exactly as Foudra makes it
  # (mrp_engine internal/events/relay.go, Sign):
  #
  #   X-Foudra-Signature: t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<body>">
  #
  # keyed with the webhook's signing secret, over the body exactly as
  # received. The time is inside the signed text, so a captured request
  # can't be replayed later with a fresh time: we also refuse an old t.
  module WebhookSignature
    module_function

    def valid?(header:, body:, secret:, tolerance: 300, now: Time.now)
      return false if header.blank? || secret.blank?

      parts = header.to_s.split(",").filter_map do |pair|
        key, value = pair.strip.split("=", 2)
        [key, value] if value
      end.to_h
      timestamp = Integer(parts["t"], 10)
      given = parts["v1"].to_s
      expected = sign(secret, timestamp, body)
      # Constant-time: a byte-by-byte compare that stops early would tell
      # an attacker how much of a forged signature was right.
      ActiveSupport::SecurityUtils.secure_compare(expected, given) &&
        (now.to_i - timestamp).abs <= tolerance
    rescue ArgumentError, TypeError
      false
    end

    # The hex signature; public so that tests (and a receiver's own test
    # tool) can make one the same way Foudra does.
    def sign(secret, timestamp, body)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
    end

    def header_for(secret, body, now: Time.now)
      "t=#{now.to_i},v1=#{sign(secret, now.to_i, body)}"
    end
  end
end
