# frozen_string_literal: true

# Foudra MRP: see https://github.com/kalopa/solidus_foudra#configuration
# Nothing is sent or synced until base_url, api_key and channel are set.
SolidusFoudra.configure do |config|
  config.base_url = ENV["FOUDRA_BASE_URL"]           # https://<company>.foudra.com
  config.api_key = ENV["FOUDRA_API_KEY"] ||
    Rails.application.credentials.dig(:foudra, :api_key)
  config.webhook_secret = ENV["FOUDRA_WEBHOOK_SECRET"] ||
    Rails.application.credentials.dig(:foudra, :webhook_secret)
  config.channel = ENV["FOUDRA_CHANNEL"]             # the Foudra channel that is this shop, e.g. "SHOP"

  # config.stock_location = nil                      # a stock location's name or id; nil = the default
  # config.part_number_column = :foudra_part_number  # the spree_variants column with the part number
  # config.sync_content = false                      # true: Foudra's name/description/image always win
  # config.send_orders_since = nil                   # nightly re-send of missed orders; set to go-live time
  # config.wanted_after_days = 0                     # sales order wanted date = order date + this
  # config.queue = :default                          # ActiveJob queue
  # config.markdown_renderer = nil                   # optional ->(markdown) { html }
end
