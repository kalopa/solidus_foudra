# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::Client do
  subject(:client) { described_class.new(sleeper: ->(s) { pauses << s }) }

  let(:pauses) { [] }

  it "sends the key as a bearer token and unwraps the data" do
    stub = stub_request(:get, foudra_url("/api/parts/7"))
      .with(headers: {"Authorization" => "Bearer #{FoudraHelpers::API_KEY}"})
      .to_return(body: '{"data":{"id":7,"available":"3.0000"}}')
    expect(client.part(7)).to eq("id" => 7, "available" => "3.0000")
    expect(stub).to have_been_requested
  end

  it "sends the Idempotency-Key and a JSON body on writes" do
    stub = stub_request(:post, foudra_url("/api/sales-orders/9/cancel"))
      .with(headers: {"Idempotency-Key" => "k1", "Content-Type" => "application/json"}, body: "{}")
      .to_return(body: '{"data":{"id":9}}')
    client.cancel_sales_order(9, idempotency_key: "k1")
    expect(stub).to have_been_requested
  end

  it "retries 429 after Retry-After, and 5xx with a growing pause" do
    stub_request(:get, foudra_url("/api/channels"))
      .to_return({status: 429, headers: {"Retry-After" => "7"}}, {status: 503},
        {body: '{"data":[{"code":"SHOP"}]}'})
    expect(client.channels).to eq([{"code" => "SHOP"}])
    expect(pauses).to eq([7, 2])
  end

  it "gives up after max_attempts with Unavailable, for the job to retry later" do
    stub_request(:get, foudra_url("/api/channels")).to_return(status: 502, body: '{"error":"bad gateway"}')
    expect { client.channels }.to raise_error(described_class::Unavailable, %r{GET /api/channels: 502 bad gateway})
    expect(a_request(:get, foudra_url("/api/channels"))).to have_been_made.times(3)
  end

  it "retries network failures" do
    stub_request(:get, foudra_url("/api/channels")).to_timeout.then.to_return(body: '{"data":[]}')
    expect(client.channels).to eq([])
  end

  it "never retries a 4xx" do
    stub_request(:post, foudra_url("/api/customers")).to_return(status: 422, body: '{"error":"name is required"}')
    expect { client.create_customer({}, idempotency_key: "k") }
      .to raise_error(described_class::Error, "POST /api/customers: 422 name is required")
    expect(a_request(:post, foudra_url("/api/customers"))).to have_been_made.once
  end

  it "maps statuses to error classes" do
    {404 => described_class::NotFound, 409 => described_class::Conflict,
     401 => described_class::Refused, 402 => described_class::Refused, 403 => described_class::Refused}
      .each do |status, klass|
        stub_request(:get, foudra_url("/api/parts/1")).to_return(status:, body: '{"error":"no"}')
        expect { client.part(1) }.to raise_error(klass) { |e| expect(e.status).to eq(status) }
      end
  end

  it "keeps the key and email addresses out of error messages" do
    stub_request(:get, foudra_url("/api/customers")).with(query: hash_including({}))
      .to_return(status: 400, body: '{"error":"bad email ann@example.com"}')
    expect { client.customers_by_email("ann@example.com") }.to raise_error(described_class::Error) { |e|
      expect(e.message).not_to include("ann@example.com")
      expect(e.message).not_to include(FoudraHelpers::API_KEY)
    }
  end

  it "walks every page" do
    stub_foudra(:get, "/api/parts", query: {page: "1", per: "100"}, body: {data: [{id: 1}], page: 1, pages: 2})
    stub_foudra(:get, "/api/parts", query: {page: "2", per: "100"}, body: {data: [{id: 2}], page: 2, pages: 2})
    expect(client.parts.map { |p| p["id"] }).to eq([1, 2])
  end

  it "finds a part by its exact number only" do
    stub_foudra(:get, "/api/parts", query: {q: "100-000001-00", per: "25"},
      body: {data: [{id: 1, part_number: "100-000001-01"},
        {id: 2, part_number: "100-000001-00"}]})
    expect(client.find_part("100-000001-00")["id"]).to eq(2)
  end

  it "refuses to run unconfigured" do
    SolidusFoudra.config.api_key = nil
    expect { client.channels }.to raise_error(described_class::Error, /not configured/)
  end

  it "leaves the secrets out of #inspect" do
    expect(SolidusFoudra.config.inspect).not_to include(FoudraHelpers::API_KEY)
    expect(SolidusFoudra.config.inspect).not_to include(FoudraHelpers::SECRET)
  end
end
