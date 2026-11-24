# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

# The part number that joins a variant to a Foudra part, and what an order
# became in Foudra.
class AddFoudraColumnsToSpreeTables < ActiveRecord::Migration[7.0]
  def change
    add_column :spree_variants, :foudra_part_number, :string
    add_index :spree_variants, :foudra_part_number

    add_column :spree_orders, :foudra_customer_id, :bigint
    add_column :spree_orders, :foudra_sales_order_id, :bigint
    add_index :spree_orders, :foudra_sales_order_id
  end
end
