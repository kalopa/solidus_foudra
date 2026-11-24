# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # POST /foudra/webhooks: checks X-Foudra-Signature over the raw body,
  # records the event id (a repeat is answered 204 and dropped), queues a
  # job with only the ids the event names, and answers 204. The job
  # re-fetches everything from the API: an event is a nudge, never data.
  class WebhooksController < ActionController::API
    def create
      body = request.raw_post
      config = SolidusFoudra.config
      unless WebhookSignature.valid?(header: request.headers["X-Foudra-Signature"], body:,
        secret: config.webhook_secret, tolerance: config.webhook_tolerance)
        SolidusFoudra.log(:warn, "webhook refused: bad or old signature")
        return head :unauthorized
      end

      event = JSON.parse(body)
      return head :bad_request unless event.is_a?(Hash) && event["id"].present?

      type = event["type"].to_s
      enqueue_jobs(type, event["data"] || {}) if WebhookEvent.record(event["id"], type)
      head :no_content
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def enqueue_jobs(type, data)
      return unless SolidusFoudra.config.enabled?

      case type
      when "stock.changed"
        id = data.dig("part", "id")
        StockJob.perform_later([id]) if id
      when "sales_order.created", "sales_order.cancelled"
        ids = Array(data["lines"]).filter_map { |l| l.dig("part", "id") }.uniq
        StockJob.perform_later(ids) if ids.any?
      when "listing.changed"
        id = data.dig("part", "id") || data.dig("listing", "part_id")
        ListingJob.perform_later(id) if id && data.dig("channel", "code") == SolidusFoudra.config.channel
      when "shipment.shipped", "shipment.updated"
        id = data.dig("shipment", "id")
        ShipmentJob.perform_later(id) if id
      end
    end
  end
end
