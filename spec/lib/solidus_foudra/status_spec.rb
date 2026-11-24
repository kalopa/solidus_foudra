# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::Status do
  let(:out) { StringIO.new }

  before { create(:stock_location) }

  it "checks the channel and listings, never printing the secrets" do
    stub_foudra(:get, "/api/channels", body: {data: [{code: "SHOP", name: "Web shop", is_active: true}]})
    stub_foudra(:get, "/api/channels/SHOP/listings",
      body: {data: [{is_listed: true, price: "1"}, {is_listed: true, price: nil}, {is_listed: false}]})
    expect(described_class.new(out:).call).to be(true)
    expect(out.string).to include("ok: Web shop").and include("2 listed of 3, 1 without a price")
    expect(out.string).not_to include(FoudraHelpers::API_KEY)
    expect(out.string).not_to include(FoudraHelpers::SECRET)
  end

  it "fails when Foudra has no such channel" do
    stub_foudra(:get, "/api/channels", body: {data: [{code: "OTHER"}]})
    stub_foudra(:get, "/api/channels/SHOP/listings", status: 404, body: {error: "not found"})
    expect(described_class.new(out:).call).to be(false)
    expect(out.string).to include("FAILED: Foudra has no channel SHOP")
  end
end
