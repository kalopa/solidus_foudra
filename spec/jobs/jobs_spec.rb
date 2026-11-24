# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidusFoudra jobs" do
  it "retries when Foudra is unavailable" do
    stub_foudra(:get, "/api/parts/7", status: 503, body: {error: "down"})
    SolidusFoudra::StockJob.perform_now([7])
    expect(SolidusFoudra::StockJob).to have_been_enqueued.with([7])
  end

  it "logs and drops a refusal" do
    stub_foudra(:get, "/api/parts/7", status: 403, body: {error: "needs the read scope"})
    expect { SolidusFoudra::StockJob.perform_now([7]) }.not_to raise_error
    expect(SolidusFoudra::StockJob).not_to have_been_enqueued
    expect(log_output).to include("dropped").and include("needs the read scope")
  end

  it "does nothing while Foudra isn't configured" do
    SolidusFoudra.config.base_url = nil
    expect { SolidusFoudra::FullSyncJob.perform_now }.not_to raise_error
  end

  it "SendOrderJob waits for the order to be complete" do
    order = create(:order)
    SolidusFoudra::SendOrderJob.perform_now(order.id)
    expect(SolidusFoudra::SendOrderJob).to have_been_enqueued.with(order.id)
  end
end
