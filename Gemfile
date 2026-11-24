# frozen_string_literal: true

source "https://rubygems.org"

# The versions Kalopa's shop runs. The extension itself asks only for
# solidus_core ~> 4.6 (the gemspec); this is the test app's Solidus.
gem "solidus", ENV.fetch("SOLIDUS_VERSION", "~> 4.6.2")

rails_version = ENV.fetch("RAILS_VERSION", "7.1")
gem "rails", "~> #{rails_version}.0"

case ENV.fetch("DB", nil)
when "postgresql"
  gem "pg"
else
  gem "sqlite3", (rails_version < "7.2") ? "~> 1.4" : "~> 2.0"
end

# json 3 dropped the quirks_mode option Rails 7.1's ActiveSupport passes.
gem "json", "< 3"

gemspec

# A local Gemfile for things only one developer wants, e.g. pry-byebug.
send(:eval_gemfile, "Gemfile-local") if File.exist? "Gemfile-local"
