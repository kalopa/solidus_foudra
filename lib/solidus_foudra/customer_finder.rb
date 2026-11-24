# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "digest"

module SolidusFoudra
  # Finds the Foudra customer for an order, or creates one:
  #
  # 1. a signed-in shopper by their Spree user id, which Foudra keeps as the
  #    customer's ref on the channel;
  # 2. anyone by the order's email, adding the user id to a customer found
  #    that way;
  # 3. else a new customer with the bill-to name, phone, addresses and the
  #    user id as its channel ref.
  #
  # An existing customer's details are never changed.
  class CustomerFinder
    def initialize(order, client: Client.new)
      @order = order
      @client = client
    end

    # The Foudra customer's id.
    def call
      by_ref || by_email || create
    end

    private

    attr_reader :order, :client

    def user_ref
      order.user_id&.to_s
    end

    def by_ref
      return unless user_ref

      client.customer_by_channel_ref(user_ref)&.fetch("id")
    end

    def by_email
      return if order.email.blank?

      found = client.customers_by_email(order.email)
      customer = found.find { |c| c["archived_at"].nil? } || found.first
      return unless customer

      if user_ref
        client.add_channel_ref(customer["id"], user_ref,
          idempotency_key: "solidus_foudra:customer-ref:#{customer["id"]}:#{user_ref}")
      end
      customer["id"]
    end

    def create
      body = attributes
      # Foudra refuses one key with two different bodies, so the key changes
      # with the customer's details.
      key = "solidus_foudra:customer:#{Digest::SHA256.hexdigest(JSON.generate(body))[0, 32]}"
      client.create_customer(body, idempotency_key: key).fetch("id")
    end

    def attributes
      bill = order.bill_address || order.ship_address
      ship = order.ship_address
      body = {
        name: bill&.name.presence || order.email,
        email: order.email.presence,
        phone: bill&.phone.presence,
        billing_address: AddressFormat.call(bill),
        shipping_address: (AddressFormat.call(ship) if ship && bill && !same_place?(ship, bill))
      }
      body[:channel_refs] = [{channel: SolidusFoudra.config.channel, ref: user_ref}] if user_ref
      body.compact
    end

    def same_place?(one, other)
      AddressFormat.call(one) == AddressFormat.call(other)
    end
  end

  # A Spree::Address as Foudra writes one.
  module AddressFormat
    module_function

    def call(address, with_name: false)
      return unless address

      out = {
        line1: address.address1,
        line2: address.address2.presence,
        city: address.city,
        region: address.state_text.presence,
        postcode: address.zipcode.presence,
        country: address.country&.iso
      }
      out = {name: address.name}.merge(out) if with_name
      out.compact
    end
  end
end
