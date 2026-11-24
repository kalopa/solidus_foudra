# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::FullSync do
  subject(:full_sync) { described_class.new }

  it "runs every step even when one fails" do
    stub_foudra(:get, "/api/channels/SHOP/listings", status: 503, body: {error: "down"})
    stub_foudra(:get, "/api/parts", query: {page: "1", per: "100"}, body: {data: [], page: 1, pages: 1})
    SolidusFoudra::WebhookEvent.create!(event_id: "old", created_at: 31.days.ago)
    SolidusFoudra::WebhookEvent.create!(event_id: "new", created_at: 1.day.ago)

    results = full_sync.call
    expect(results[:products]).to include("503")
    expect(results.except(:products).values).to all(eq(:ok))
    expect(SolidusFoudra::WebhookEvent.pluck(:event_id)).to eq(["new"])
  end

  it "re-sends orders since send_orders_since that never reached Foudra, and only those" do
    create(:completed_order_with_totals)
    create(:completed_order_with_totals).update_columns(completed_at: 2.days.ago)
    create(:completed_order_with_totals).update_columns(foudra_sales_order_id: 9)
    SolidusFoudra.config.send_orders_since = 1.day.ago
    expect_any_instance_of(SolidusFoudra::OrderSender).to receive(:send_order).once
    expect(full_sync.call(%i[resend])).to eq(resend: :ok)
  end

  it "re-sends nothing without send_orders_since" do
    create(:completed_order_with_totals)
    expect_any_instance_of(SolidusFoudra::OrderSender).not_to receive(:send_order)
    full_sync.call(%i[resend])
  end
end
