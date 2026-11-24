# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::StockSync do
  subject(:sync) { described_class.new }

  let!(:location) { create(:stock_location, default: true) }
  let!(:variant) { create(:variant, foudra_part_number: "100-000001-00") }

  def count
    location.stock_item(variant).reload.count_on_hand
  end

  it "sets the count on hand to available, rounded down" do
    expect(sync.update("part_number" => "100-000001-00", "available" => "7.75")).to eq(1)
    expect(count).to eq(7)
  end

  it "never goes below zero" do
    sync.update("part_number" => "100-000001-00", "available" => "-3")
    expect(count).to eq(0)
  end

  it "leaves variants that don't track inventory" do
    variant.update!(track_inventory: false)
    location.stock_item(variant).set_count_on_hand(4)
    expect(sync.update("part_number" => "100-000001-00", "available" => "9")).to eq(0)
    expect(count).to eq(4)
  end

  it "re-fetches parts by id" do
    stub_foudra(:get, "/api/parts/7", body: {data: {id: 7, part_number: "100-000001-00", available: "12"}})
    stub_foudra(:get, "/api/parts/8", status: 404, body: {error: "not found"})
    sync.update_parts([7, 8])
    expect(count).to eq(12)
    expect(log_output).to include("part 8: not found")
  end

  it "uses the configured part number column" do
    SolidusFoudra.config.part_number_column = :sku
    variant.update!(sku: "200-000002-00")
    sync.update("part_number" => "200-000002-00", "available" => "3")
    expect(count).to eq(3)
  end
end
