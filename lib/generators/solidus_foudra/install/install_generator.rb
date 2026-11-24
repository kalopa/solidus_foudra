# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

module SolidusFoudra
  module Generators
    # bin/rails generate solidus_foudra:install
    #
    # Writes the initializer, mounts the engine at /foudra (the webhook is
    # POST /foudra/webhooks) and copies the migrations.
    class InstallGenerator < Rails::Generators::Base
      class_option :auto_run_migrations, type: :boolean, default: false
      source_root File.expand_path("templates", __dir__)

      def self.exit_on_failure?
        true
      end

      def copy_initializer
        template "initializer.rb", "config/initializers/solidus_foudra.rb"
      end

      def mount_engine
        routes = File.join(destination_root, "config/routes.rb")
        return if File.exist?(routes) && File.read(routes).include?("SolidusFoudra::Engine")

        route 'mount SolidusFoudra::Engine, at: "/foudra"'
      end

      def add_migrations
        run "bin/rails railties:install:migrations FROM=solidus_foudra"
      end

      def run_migrations
        run_migrations = options[:auto_run_migrations] ||
          ["", "y", "Y"].include?(ask("Would you like to run the migrations now? [Y/n]"))
        if run_migrations
          run "bin/rails db:migrate"
        else
          say "Skipping bin/rails db:migrate, don't forget to run it!"
        end
      end
    end
  end
end
