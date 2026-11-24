# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "json"
require "net/http"
require "uri"

module SolidusFoudra
  # A small client for Foudra's JSON API (foudra.com/developers), on
  # Net::HTTP so the gem adds no runtime dependency.
  #
  # Foudra's conventions it relies on: `Authorization: Bearer fdr_…`;
  # answers wrapped as {"data": …} (lists add page/pages/total); errors as
  # {"error": "…"} with a status that means what it says; decimals as
  # strings; Idempotency-Key on writes makes a repeat return the first answer.
  class Client
    class Error < StandardError
      attr_reader :status, :path

      def initialize(message, status: nil, path: nil)
        super(Redact.call(message))
        @status = status
        @path = path
      end
    end

    # 404: not there, or in another company.
    class NotFound < Error; end
    # 409: not in a state that allows it (e.g. cancelling a shipped order).
    class Conflict < Error; end
    # 401/402/403: the key, the subscription or the role. Retrying won't help
    # until a person fixes it.
    class Refused < Error; end
    # 429, 5xx and network failures that outlasted our own attempts. Jobs
    # retry these later with ActiveJob's backoff.
    class Unavailable < Error; end

    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze
    NETWORK_ERRORS = [IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
      Net::OpenTimeout, Net::ReadTimeout, SocketError].freeze

    attr_reader :config

    # sleeper is how long-running pauses happen; tests pass a no-op.
    def initialize(config = SolidusFoudra.config, sleeper: ->(seconds) { sleep(seconds) })
      @config = config
      @sleeper = sleeper
    end

    def get(path, params = {})
      request(:get, path, params:)
    end

    def post(path, body = {}, idempotency_key: nil)
      request(:post, path, body:, idempotency_key:)
    end

    def put(path, body = {}, idempotency_key: nil)
      request(:put, path, body:, idempotency_key:)
    end

    # Every row of a paged list, a page of 100 at a time.
    def each_page(path, params = {}, &block)
      return enum_for(:each_page, path, params) unless block

      page = 1
      loop do
        out = get(path, params.merge(page:, per: 100))
        Array(out["data"]).each(&block)
        break if page >= out.fetch("pages", 1).to_i

        page += 1
      end
    end

    # --- The calls the gem makes ------------------------------------------

    def part(id)
      get("/api/parts/#{Integer(id)}")["data"]
    end

    # A part by its exact part number. ?q= also matches other text, so
    # compare; nil when Foudra has no such part.
    def find_part(part_number)
      get("/api/parts", q: part_number, per: 25)["data"].find { |p| p["part_number"] == part_number }
    end

    def parts(&)
      each_page("/api/parts", &)
    end

    def images(part_id)
      get("/api/parts/#{Integer(part_id)}/images")["data"]
    end

    # The bytes of a file the API names by path (an image's url).
    def download(path)
      request(:get, path, raw: true)
    end

    def channels
      get("/api/channels")["data"]
    end

    # Every listing on the channel, listed or not (not paged).
    def listings(channel = config.channel)
      get("/api/channels/#{escape(channel)}/listings")["data"]
    end

    def put_listing(part_id, attrs, channel: config.channel)
      put("/api/channels/#{escape(channel)}/listings/#{Integer(part_id)}", attrs)["data"]
    end

    def customers_by_email(email)
      get("/api/customers", email:, per: 10)["data"]
    end

    def create_customer(attrs, idempotency_key:)
      post("/api/customers", attrs, idempotency_key:)["data"]
    end

    def find_sales_order(channel_order_ref, channel: config.channel)
      get("/api/sales-orders", channel:, channel_order_ref:, per: 10)["data"].first
    end

    def sales_order(id)
      get("/api/sales-orders/#{Integer(id)}")["data"]
    end

    def create_sales_order(attrs, idempotency_key:)
      post("/api/sales-orders", attrs, idempotency_key:)["data"]
    end

    def cancel_sales_order(id, idempotency_key:)
      post("/api/sales-orders/#{Integer(id)}/cancel", {}, idempotency_key:)["data"]
    end

    def shipment(id)
      get("/api/shipments/#{Integer(id)}")["data"]
    end

    def shipments_for(sales_order_id, status: "shipped")
      each_page("/api/shipments", sales_order_id: Integer(sales_order_id), status:).to_a
    end

    private

    def escape(segment)
      URI.encode_www_form_component(segment.to_s)
    end

    def request(method, path, params: nil, body: nil, idempotency_key: nil, raw: false)
      raise Error, "Foudra is not configured (base_url, api_key, channel)" unless config.enabled?

      uri = URI.join(config.base_url.to_s.chomp("/") + "/", path.delete_prefix("/"))
      uri.query = URI.encode_www_form(params) if params.present?
      attempt = 0
      begin
        attempt += 1
        response = perform(method, uri, body, idempotency_key)
        status = response.code.to_i
        if RETRY_STATUSES.include?(status) && attempt < config.max_attempts
          @sleeper.call(pause(attempt, response))
          raise RetryNow
        end
        handle(response, method, path, raw)
      rescue RetryNow
        retry
      rescue *NETWORK_ERRORS => e
        # Every write we make carries an Idempotency-Key and GET and PUT are
        # safe to repeat, so a network failure is always safe to retry.
        if attempt < config.max_attempts
          @sleeper.call(pause(attempt, nil))
          retry
        end
        raise Unavailable.new("#{method.upcase} #{path}: #{e.class}", path:)
      end
    end

    class RetryNow < StandardError; end
    private_constant :RetryNow

    def perform(method, uri, body, idempotency_key)
      klass = {get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put}.fetch(method)
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{config.api_key}"
      req["Accept"] = "application/json"
      req["User-Agent"] = "solidus_foudra/#{SolidusFoudra::VERSION}"
      req["Idempotency-Key"] = idempotency_key if idempotency_key
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: config.open_timeout,
        read_timeout: config.read_timeout) do |http|
        http.request(req)
      end
    end

    # Retry-After when Foudra gives one (429), else 1s, 2s, 4s…
    def pause(attempt, response)
      after = response&.[]("Retry-After").to_i
      after.positive? ? [after, 60].min : 2**(attempt - 1)
    end

    def handle(response, method, path, raw)
      status = response.code.to_i
      if status.between?(200, 299)
        return response.body if raw

        return response.body.blank? ? {} : JSON.parse(response.body)
      end

      message = "#{method.upcase} #{path}: #{status} #{error_text(response)}".strip
      klass = case status
      when 404 then NotFound
      when 409 then Conflict
      when 401, 402, 403 then Refused
      when *RETRY_STATUSES then Unavailable
      else Error
      end
      raise klass.new(message, status:, path:)
    end

    def error_text(response)
      JSON.parse(response.body.to_s)["error"].to_s
    rescue JSON::ParserError, TypeError, NoMethodError
      response.body.to_s[0, 200]
    end
  end
end
