# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# Load the Rails sandbox environment first so Railties (like Kredis) can hook into Rails properly
require_relative "sandbox/config/environment"

# Ensure Kredis is properly loaded before loading other dependencies
require "kredis"

# Configure Kredis after Rails is loaded but before loading zorram
Kredis.configurator = Rails.application if defined?(Rails) && Rails.respond_to?(:application) && Rails.application

# Now load other dependencies that might depend on Kredis
require "aasm"
require "zorram"

require "rspec/rails"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

# I18n.load_path += Dir["#{File.expand_path('config/locales')}/*.yml"]

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect

    # Configures the maximum character length that RSpec will print while
    # formatting an object. You can set length to nil to prevent RSpec from
    # doing truncation.
    c.max_formatted_output_length = nil
  end
end
