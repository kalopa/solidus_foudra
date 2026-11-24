# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  # The variants a Foudra part number names, through the configured column.
  module PartNumbers
    module_function

    def column
      SolidusFoudra.config.part_number_column
    end

    def of(variant)
      variant.public_send(column).presence
    end

    # Live (not deleted) variants with this part number.
    def variants(part_number)
      Spree::Variant.where(column => part_number.to_s)
    end

    def deleted_variants(part_number)
      Spree::Variant.with_discarded.discarded.where(column => part_number.to_s)
    end
  end
end
