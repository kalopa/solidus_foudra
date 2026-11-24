# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::ProductSync do
  subject(:sync) { described_class.new }

  let(:currency) { Spree::Config.currency }

  def listing(**attrs)
    {"id" => 1, "part_id" => 7, "part_number" => "100-000001-00", "part_name" => "Widget",
     "part_is_active" => true, "channel_part_number" => nil, "is_listed" => true,
     "price" => "249", "currency" => currency}.merge(attrs.transform_keys(&:to_s))
  end

  def stub_part(**attrs)
    stub_foudra(:get, "/api/parts/7", body: {data: {id: 7, part_number: "100-000001-00", name: "Widget",
                                                    description: "A **fine** widget."}.merge(attrs)})
  end

  def stub_write_back(sku)
    stub_request(:put, foudra_url("/api/channels/SHOP/listings/7"))
      .with(body: {channel_part_number: sku}).to_return(body: '{"data":{}}')
  end

  before { create(:shipping_category) }

  describe "a listed part with no variant" do
    before do
      stub_part
      stub_foudra(:get, "/api/parts/7/images", body: {data: []})
    end

    it "creates a product: SKU = the part number, price, Markdown description, available now" do
      write_back = stub_write_back("100-000001-00")
      sync.sync(listing)
      product = Spree::Variant.find_by!(foudra_part_number: "100-000001-00").product
      expect(product).to have_attributes(name: "Widget", description: "<p>A <strong>fine</strong> widget.</p>")
      expect(product.master.sku).to eq("100-000001-00")
      expect(product.price).to eq(249)
      expect(product).to be_available
      expect(write_back).to have_been_requested
    end

    it "makes none without a price in the shop's currency" do
      sync.sync(listing(price: nil))
      sync.sync(listing(currency: "XXX"))
      expect(Spree::Product.count).to eq(0)
    end

    it "makes none when a deleted variant had the number, or another has the SKU" do
      create(:variant, foudra_part_number: "100-000001-00").discard
      sync.sync(listing)
      expect(Spree::Product.kept.count).to eq(1) # just the deleted variant's own product
      expect(log_output).to include("a deleted variant had this number")
    end

    it "makes none when another variant already has the part number as its SKU" do
      create(:variant, sku: "100-000001-00")
      expect { sync.sync(listing) }.not_to change(Spree::Product, :count)
      expect(log_output).to include("another variant has this SKU")
    end

    it "attaches the part's own first image, never its category's" do
      stub_foudra(:get, "/api/parts/7/images", body: {data: [
        {id: 1, url: "/api/images/1", filename: "cat.png", content_type: "image/png", from_category: true}
      ]})
      stub_write_back("100-000001-00")
      sync.sync(listing)
      expect(Spree::Image.count).to eq(0)
    end
  end

  describe "a listed part a variant has" do
    let!(:variant) { create(:variant, foudra_part_number: "100-000001-00", sku: "W-1", price: 10) }

    it "sets the price and clears a discontinuation, writing back the SKU" do
      variant.product.update!(discontinue_on: 1.day.ago)
      write_back = stub_write_back("W-1")
      sync.sync(listing(price: "12.50"))
      expect(variant.reload.price).to eq(12.5)
      expect(variant.product.reload.discontinue_on).to be_nil
      expect(write_back).to have_been_requested
    end

    it "sets a price in another currency alongside" do
      sync.sync(listing(currency: "EUR", price: "11", channel_part_number: "W-1"))
      expect(variant.prices.find_by(currency: "EUR").amount).to eq(11)
      expect(variant.reload.price).to eq(10)
    end

    it "leaves name and description unless sync_content" do
      sync.sync(listing(channel_part_number: "W-1"))
      expect(variant.product.reload.name).not_to eq("Widget")
    end

    it "logs a SKU already used on another part, and carries on" do
      stub_request(:put, foudra_url("/api/channels/SHOP/listings/7"))
        .to_return(status: 409, body: '{"error":"channel part number in use"}')
      expect { sync.sync(listing) }.not_to raise_error
      expect(log_output).to include("SKU not written back")
    end
  end

  describe "unlisted" do
    let!(:variant) { create(:variant, foudra_part_number: "100-000001-00") }

    it "discontinues the product, also when the part is archived" do
      sync.sync(listing(is_listed: false))
      expect(variant.product.reload).to be_discontinued
    end

    it "discontinues when the part is archived" do
      sync.sync(listing(part_is_active: false))
      expect(variant.product.reload).to be_discontinued
    end

    it "leaves the product when another of its variants is still listed" do
      create(:variant, product: variant.product, foudra_part_number: "100-000002-00")
      stub_foudra(:get, "/api/channels/SHOP/listings",
        body: {data: [listing(is_listed: false), listing(part_id: 8, part_number: "100-000002-00")]})
      sync.sync(listing(is_listed: false))
      expect(variant.product.reload).not_to be_discontinued
    end

    it "treats a part never listed on the channel as unlisted" do
      stub_foudra(:get, "/api/channels/SHOP/listings", query: {part_id: "7"}, body: {data: []})
      stub_part
      sync.sync_part(7)
      expect(variant.product.reload).to be_discontinued
    end
  end

  it "sync_all discontinues variants whose part isn't on the channel at all" do
    gone = create(:variant, foudra_part_number: "999-000000-00")
    stub_foudra(:get, "/api/channels/SHOP/listings", body: {data: []})
    sync.sync_all
    expect(gone.product.reload).to be_discontinued
  end
end
