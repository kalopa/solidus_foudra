# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # Takes customers' email addresses and API keys out of text bound for a
  # log. The gem never puts them there on purpose; this is for what it
  # can't control, such as an error message Foudra wrote about a request.
  module Redact
    EMAIL = /[^\s@<>"',;:()]+@[^\s@<>"',;:()]+\.[A-Za-z]{2,}/
    KEY = /\bfd(?:r|o|or)_[A-Za-z0-9]+/

    def self.call(text)
      text.to_s.gsub(EMAIL, "[email]").gsub(KEY, "[key]")
    end
  end
end
