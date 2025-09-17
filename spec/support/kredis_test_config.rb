# frozen_string_literal: true

# Minimal Kredis configuration for test environment.
# Ensure Kredis knows about the Rails application so it can resolve config/redis/shared.yml
# via Kredis.configurator (see Kredis::Connections#configured_for).

if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
  require "kredis"
  Kredis.configurator = Rails.application
end
