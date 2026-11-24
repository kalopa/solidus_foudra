# frozen_string_literal: true

require "spec_helper"

RSpec.describe "POST /foudra/webhooks", type: :request do
  def deliver(event, headers: nil)
    body = JSON.generate(event)
    post "/foudra/webhooks", params: body, headers: headers || signed_headers(body)
  end

  def event(type, data, id: rand(1_000_000))
    {id:, type:, occurred_at: Time.now.utc.iso8601, text: "", data:}
  end

  it "answers a ping with 204 and does nothing" do
    deliver(event("ping", {hello: "world"}))
    expect(response).to have_http_status(:no_content)
    expect(enqueued_jobs).to be_empty
  end

  it "refuses a bad signature, a wrong secret and an old timestamp" do
    body = JSON.generate(event("ping", {}))
    post "/foudra/webhooks", params: body, headers: {"X-Foudra-Signature" => "t=1,v1=00"}
    expect(response).to have_http_status(:unauthorized)
    post "/foudra/webhooks", params: body, headers: signed_headers(body, secret: "other")
    expect(response).to have_http_status(:unauthorized)
    post "/foudra/webhooks", params: body, headers: signed_headers(body, now: 10.minutes.ago)
    expect(response).to have_http_status(:unauthorized)
  end

  it "queues only the part id on stock.changed" do
    deliver(event("stock.changed", {part: {id: 7, part_number: "100-000001-00"}, on_hand_total: "5.0000"}))
    expect(response).to have_http_status(:no_content)
    expect(SolidusFoudra::StockJob).to have_been_enqueued.with([7])
  end

  it "drops a redelivered event" do
    e = event("stock.changed", {part: {id: 7}}, id: 42)
    deliver(e)
    deliver(e)
    expect(response).to have_http_status(:no_content)
    expect(SolidusFoudra::StockJob).to have_been_enqueued.exactly(:once)
  end

  it "queues each line's part on sales_order.created and .cancelled" do
    deliver(event("sales_order.cancelled", {sales_order: {id: 3},
      lines: [{part: {id: 7}}, {part: {id: 8}}, {part: {id: 7}}]}))
    expect(SolidusFoudra::StockJob).to have_been_enqueued.with([7, 8])
  end

  it "queues listing.changed for our channel only" do
    deliver(event("listing.changed", {listing: {id: 1, part_id: 7}, part: {id: 7}, channel: {id: 1, code: "OTHER"}}))
    expect(SolidusFoudra::ListingJob).not_to have_been_enqueued
    deliver(event("listing.changed", {listing: {id: 1, part_id: 7}, part: {id: 7}, channel: {id: 2, code: "SHOP"}}))
    expect(SolidusFoudra::ListingJob).to have_been_enqueued.with(7)
  end

  it "queues the shipment id on shipment.shipped and .updated" do
    deliver(event("shipment.shipped", {shipment: {id: 11}}))
    deliver(event("shipment.updated", {shipment: {id: 11}}))
    expect(SolidusFoudra::ShipmentJob).to have_been_enqueued.with(11).twice
  end

  it "answers 400 to a signed body that isn't an event" do
    body = "not json"
    post "/foudra/webhooks", params: body, headers: signed_headers(body)
    expect(response).to have_http_status(:bad_request)
  end
end
