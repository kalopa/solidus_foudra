# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "bigdecimal"
require "stringio"

module SolidusFoudra
  # Makes the shop's products match the channel's listings:
  #
  # - listed, no variant with its number: a new product (master only);
  # - listed, a variant has its number: adopted, its price set and any
  #   discontinuation cleared (name, description and image only with
  #   sync_content);
  # - unlisted, never listed or the part archived: the product is
  #   discontinued, unless another of its variants is still listed.
  #
  # The shop's SKU is written back as the listing's channel_part_number.
  # Nothing is ever deleted.
  class ProductSync
    def initialize(client: Client.new)
      @client = client
    end

    # One part, after listing.changed.
    def sync_part(part_id)
      listing = client.listing(part_id)
      if listing
        sync(listing)
      else
        # Never listed (or the listing removed): unlisted.
        part = client.part(part_id)
        unlist(part["part_number"].to_s, nil)
      end
    rescue Client::NotFound
      SolidusFoudra.log(:warn, "part #{part_id}: not found in Foudra")
    end

    # Every listing on the channel, then every variant whose part isn't on
    # it at all.
    def sync_all
      listings = client.listings
      @listed_numbers = listings.select { |l| listed?(l) }.map { |l| l["part_number"] }.to_set
      listings.each do |listing|
        sync(listing)
      rescue Client::Unavailable
        raise
      rescue Client::Error, ActiveRecord::ActiveRecordError => e
        SolidusFoudra.log(:error, "listing #{listing["part_number"]}: #{e.message}")
      end
      on_channel = listings.map { |l| l["part_number"] }.to_set
      Spree::Variant.where.not(PartNumbers.column => [nil, ""]).find_each do |variant|
        number = PartNumbers.of(variant)
        unlist(number, nil) unless on_channel.include?(number)
      end
    end

    def sync(listing)
      number = listing["part_number"].to_s
      return if number.empty?

      if listed?(listing)
        variants = PartNumbers.variants(number).to_a
        variants.empty? ? create(listing) : variants.each { |v| adopt(v, listing) }
      else
        unlist(number, listing)
      end
    end

    private

    attr_reader :client

    def listed?(listing)
      listing["is_listed"] && listing["part_is_active"] != false
    end

    def shop_currency
      @shop_currency ||= Spree::Store.default.try(:default_currency).presence || Spree::Config.currency
    end

    def currency_of(listing)
      listing["currency"].presence || shop_currency
    end

    def price_of(listing)
      BigDecimal(listing["price"].to_s) if listing["price"].present?
    rescue ArgumentError
      nil
    end

    def create(listing)
      number = listing["part_number"]
      price = price_of(listing)
      if price.nil? || currency_of(listing) != shop_currency
        return SolidusFoudra.log(:info, "#{number}: listed without a #{shop_currency} price; no product made")
      end
      if PartNumbers.deleted_variants(number).exists?
        return SolidusFoudra.log(:info, "#{number}: a deleted variant had this number; no product made")
      end
      if Spree::Variant.with_discarded.exists?(sku: number)
        return SolidusFoudra.log(:warn, "#{number}: another variant has this SKU; no product made")
      end

      part = client.part(listing["part_id"])
      product = Spree::Product.new(
        name: part["name"].presence || listing["part_name"].presence || number,
        description: Markdown.render(part["description"]),
        price:,
        sku: number,
        available_on: Time.current,
        shipping_category: shipping_category
      )
      product.master.public_send(:"#{PartNumbers.column}=", number)
      product.save!
      attach_image(product.master, part["id"])
      write_back(listing, product.master)
      SolidusFoudra.log(:info, "#{number}: product created")
    end

    def adopt(variant, listing)
      set_price(variant, listing)
      product = variant.product
      product.update!(discontinue_on: nil) if product.discontinue_on.present?
      if SolidusFoudra.config.sync_content && variant.is_master?
        part = client.part(listing["part_id"])
        product.update!(name: part["name"], description: Markdown.render(part["description"])) if part["name"].present?
        attach_image(variant, part["id"]) if variant.images.empty?
      end
      write_back(listing, variant)
    end

    # In the shop's currency: the default price and its VAT prices. In
    # another currency: a price in that currency.
    def set_price(variant, listing)
      amount = price_of(listing)
      return unless amount

      currency = currency_of(listing)
      prices = variant.prices.where(currency:)
      if currency == shop_currency && prices.exists?
        prices.each { |p| p.update!(amount:) unless p.amount == amount }
      else
        price = prices.find_or_initialize_by(country_iso: nil)
        price.update!(amount:) unless price.persisted? && price.amount == amount
      end
    end

    # Solidus discontinues products, not variants.
    def unlist(number, _listing)
      return if number.blank?

      PartNumbers.variants(number).includes(:product).find_each do |variant|
        product = variant.product
        next if product.discontinued?

        others = product.variants_including_master.where.not(id: variant.id).filter_map { |v| PartNumbers.of(v) }
        if others.any? { |n| listed_number?(n) }
          SolidusFoudra.log(:info, "#{number}: unlisted, but #{product.slug} has another listed variant; left")
          next
        end
        product.update!(discontinue_on: Time.current)
        SolidusFoudra.log(:info, "#{number}: unlisted; #{product.slug} discontinued")
      end
    end

    def listed_number?(number)
      @listed_numbers ||= client.listings.select { |l| listed?(l) }.map { |l| l["part_number"] }.to_set
      @listed_numbers.include?(number)
    end

    def write_back(listing, variant)
      sku = variant.sku.presence
      return if sku.nil? || listing["channel_part_number"] == sku

      client.put_listing(listing["part_id"], {channel_part_number: sku})
    rescue Client::Conflict => e
      SolidusFoudra.log(:warn, "#{listing["part_number"]}: SKU not written back: #{e.message}")
    end

    # The part's own first image, never its category's.
    def attach_image(variant, part_id)
      image = client.images(part_id).find { |i| !i["from_category"] }
      return unless image

      bytes = client.download(image["url"])
      Spree::Image.create!(viewable: variant, alt: variant.name,
        attachment: {io: StringIO.new(bytes), filename: image["filename"].presence || "image",
                     content_type: image["content_type"]})
    rescue Client::Unavailable
      raise
    rescue Client::Error, ActiveRecord::ActiveRecordError => e
      SolidusFoudra.log(:warn, "part #{part_id}: image not added: #{e.message}")
    end

    def shipping_category
      Spree::ShippingCategory.order(:id).first || Spree::ShippingCategory.create!(name: "Default")
    end
  end
end
