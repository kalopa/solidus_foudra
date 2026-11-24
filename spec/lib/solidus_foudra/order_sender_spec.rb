# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::OrderSender do
  subject(:sender) { described_class.new(order) }

  let(:variant) { create(:variant, foudra_part_number: "100-000001-00", price: 20) }
  let(:other) { create(:variant, price: 5) }
  let(:user) { create(:user) }
  let(:order) do
    create(:completed_order_with_totals, user:,
      line_items_attributes: [{variant:, quantity: 2, price: 20}, {variant: other, quantity: 1, price: 5}])
      .tap { |o| o.update_columns(email: "ann@example.com") }
  end

  def stub_customer_by_ref(data)
    stub_foudra(:get, "/api/customers", query: {channel: "SHOP", channel_ref: user.id.to_s, per: "10"},
      body: {data:})
  end

  def stub_create_order
    stub_request(:post, foudra_url("/api/sales-orders"))
      .with(headers: {"Idempotency-Key" => "solidus_foudra:order:#{order.number}"})
      .to_return(body: JSON.generate(data: {id: 77, number: "SO-1"}))
  end

  it "sends the lines with part numbers, for the customer found by the shop's user id" do
    stub_customer_by_ref([{id: 5}])
    create_order = stub_create_order
    expect(sender.send_order).to eq(77)

    expect(create_order.with { |req|
      body = JSON.parse(req.body)
      expect(body).to include("channel" => "SHOP", "channel_order_ref" => order.number,
        "customer_id" => 5, "customer_reference" => order.number, "currency" => order.currency,
        "ordered_at" => order.completed_at.to_date.iso8601)
      expect(body["lines"]).to eq([{"part_number" => "100-000001-00", "quantity" => "2", "unit_price" => "20.0"}])
      expect(body["ship_to"]).to include("name" => order.ship_address.name, "line1" => order.ship_address.address1)
      true
    }).to have_been_requested
    expect(order.reload).to have_attributes(foudra_customer_id: 5, foudra_sales_order_id: 77)
  end

  it "adds the user id to a customer found by email" do
    stub_customer_by_ref([])
    stub_foudra(:get, "/api/customers", query: {email: "ann@example.com", per: "10"}, body: {data: [{id: 6}]})
    add_ref = stub_request(:put, foudra_url("/api/customers/6"))
      .with(body: {channel_refs: [{channel: "SHOP", ref: user.id.to_s}]}).to_return(body: '{"data":{"id":6}}')
    stub_create_order
    sender.send_order
    expect(add_ref).to have_been_requested
    expect(order.reload.foudra_customer_id).to eq(6)
  end

  it "creates a customer when none is found, keyed by a digest of the body" do
    stub_customer_by_ref([])
    stub_foudra(:get, "/api/customers", query: {email: "ann@example.com", per: "10"}, body: {data: []})
    create_customer = stub_request(:post, foudra_url("/api/customers"))
      .with(headers: {"Idempotency-Key" => /\Asolidus_foudra:customer:\h{32}\z/})
      .to_return(body: '{"data":{"id":8}}')
    stub_create_order
    sender.send_order
    expect(create_customer.with { |req|
      body = JSON.parse(req.body)
      expect(body).to include("name" => order.bill_address.name, "email" => "ann@example.com",
        "channel_refs" => [{"channel" => "SHOP", "ref" => user.id.to_s}])
      expect(body["billing_address"]).to include("country" => order.bill_address.country.iso)
      true
    }).to have_been_requested
  end

  it "sends nothing when no line has a part number" do
    variant.update!(foudra_part_number: nil)
    expect(sender.send_order).to be_nil
    expect(a_request(:any, /foudra/)).not_to have_been_made
  end

  it "doesn't send an order twice" do
    order.update_columns(foudra_sales_order_id: 77)
    expect(sender.send_order).to eq(77)
    expect(a_request(:any, /foudra/)).not_to have_been_made
  end

  it "never logs the customer's email" do
    stub_customer_by_ref([])
    stub_foudra(:get, "/api/customers", query: {email: "ann@example.com", per: "10"},
      status: 422, body: {error: "bad email ann@example.com"})
    expect { sender.send_order }.to raise_error(SolidusFoudra::Client::Error)
    expect(log_output).not_to include("ann@example.com")
  end

  describe "#cancel_order" do
    it "cancels the remembered sales order" do
      order.update_columns(foudra_sales_order_id: 77)
      cancel = stub_request(:post, foudra_url("/api/sales-orders/77/cancel"))
        .with(headers: {"Idempotency-Key" => "solidus_foudra:cancel:#{order.number}"})
        .to_return(body: '{"data":{"id":77}}')
      sender.cancel_order
      expect(cancel).to have_been_requested
    end

    it "finds the sales order by the order number, and logs a 409" do
      stub_foudra(:get, "/api/sales-orders", query: {channel: "SHOP", channel_order_ref: order.number, per: "10"},
        body: {data: [{id: 78}]})
      stub_foudra(:post, "/api/sales-orders/78/cancel", status: 409, body: {error: "some of it has already shipped"})
      expect { sender.cancel_order }.not_to raise_error
      expect(log_output).to include("already shipped")
    end
  end
end
