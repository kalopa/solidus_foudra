# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::ShipmentSync do
  subject(:sync) { described_class.new }

  let(:variant) { create(:variant, foudra_part_number: "100-000001-00") }
  let(:order) { create(:order_ready_to_ship, line_items_attributes: [{variant:, quantity: 3}]) }

  def shipment(**attrs)
    {"id" => 11, "number" => "SH-1", "status" => "shipped", "sales_order_id" => 77,
     "tracking_number" => "1Z999", "shipped_at" => "2026-11-24T10:00:00Z",
     "lines" => [{"part_number" => "100-000001-00", "quantity" => "3"}]}.merge(attrs.transform_keys(&:to_s))
  end

  before do
    stub_foudra(:get, "/api/sales-orders/77", body: {data: {id: 77, channel: "SHOP", channel_order_ref: order.number}})
  end

  it "ships the units in one carton with the Foudra number and tracking" do
    sync.sync(shipment)
    carton = Spree::Carton.find_by!(external_number: "SH-1")
    expect(carton.tracking).to eq("1Z999")
    expect(carton.inventory_units.count).to eq(3)
    expect(order.reload.shipments.first).to be_shipped
    expect(carton.suppress_email).to be_falsey # Solidus sends its shipped email
  end

  it "ships only as many units as Foudra shipped" do
    sync.sync(shipment(lines: [{"part_number" => "100-000001-00", "quantity" => "2"}]))
    expect(order.inventory_units.select(&:shipped?).size).to eq(2)
    expect(order.reload.shipments.first).not_to be_shipped
  end

  it "on a repeat makes no second carton and only corrects the tracking" do
    sync.sync(shipment)
    sync.sync(shipment(tracking_number: "1Z000"))
    expect(Spree::Carton.where(external_number: "SH-1").count).to eq(1)
    expect(Spree::Carton.find_by!(external_number: "SH-1").tracking).to eq("1Z000")
  end

  it "ignores a shipment on another channel, or not yet shipped" do
    stub_foudra(:get, "/api/sales-orders/77", body: {data: {id: 77, channel: "OTHER", channel_order_ref: order.number}})
    sync.sync(shipment)
    sync.sync(shipment(status: "packed"))
    expect(Spree::Carton.count).to eq(0)
  end

  it "re-fetches the shipment by id" do
    stub_foudra(:get, "/api/shipments/11", body: {data: shipment})
    sync.sync_id(11)
    expect(Spree::Carton.count).to eq(1)
  end
end
