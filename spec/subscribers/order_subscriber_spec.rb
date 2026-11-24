# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::OrderSubscriber do
  let(:order) { create(:completed_order_with_totals) }

  it "queues SendOrderJob when an order is finalized" do
    Spree::Bus.publish(:order_finalized, order:)
    expect(SolidusFoudra::SendOrderJob).to have_been_enqueued.with(order.id)
  end

  it "queues CancelOrderJob when an order is cancelled" do
    Spree::Bus.publish(:order_canceled, order:)
    expect(SolidusFoudra::CancelOrderJob).to have_been_enqueued.with(order.id)
  end

  it "queues nothing when Foudra isn't configured" do
    SolidusFoudra.config.api_key = nil
    Spree::Bus.publish(:order_finalized, order:)
    expect(SolidusFoudra::SendOrderJob).not_to have_been_enqueued
  end
end
