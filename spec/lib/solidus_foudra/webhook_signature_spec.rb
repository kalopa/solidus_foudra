# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::WebhookSignature do
  let(:secret) { "shh" }
  let(:body) { '{"id":412,"type":"ping","data":{"hello":"world"}}' }
  let(:now) { Time.zone.at(1_700_000_000) }

  # The same computation as mrp_engine internal/events/relay.go Sign:
  # hex HMAC-SHA256 over "<t>.<body>".
  it "matches the signature Foudra computes" do
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "1700000000.#{body}")
    expect(described_class.header_for(secret, body, now:)).to eq("t=1700000000,v1=#{expected}")
  end

  it "accepts a good signature" do
    header = described_class.header_for(secret, body, now:)
    expect(described_class.valid?(header:, body:, secret:, now:)).to be true
  end

  it "refuses a signature over a different body" do
    header = described_class.header_for(secret, body, now:)
    expect(described_class.valid?(header:, body: body.sub("412", "413"), secret:, now:)).to be false
  end

  it "refuses another secret" do
    header = described_class.header_for("other", body, now:)
    expect(described_class.valid?(header:, body:, secret:, now:)).to be false
  end

  it "refuses an old timestamp, and one from the future" do
    header = described_class.header_for(secret, body, now:)
    expect(described_class.valid?(header:, body:, secret:, now: now + 301)).to be false
    expect(described_class.valid?(header:, body:, secret:, now: now - 301)).to be false
    expect(described_class.valid?(header:, body:, secret:, now: now + 299)).to be true
  end

  it "refuses missing and malformed headers, and a missing secret" do
    good = described_class.header_for(secret, body, now:)
    ["", nil, "v1=abc", "t=abc,v1=def", "t=1700000000", "garbage"].each do |header|
      expect(described_class.valid?(header:, body:, secret:, now:)).to be(false), header.inspect
    end
    expect(described_class.valid?(header: good, body:, secret: nil, now:)).to be false
  end
end
