# frozen_string_literal: true

module Zorram
  class Engine < ::Rails::Engine
    isolate_namespace Zorram

    config.zorram = Zorram::Configuration.new

    def self.configure
      yield(config.zorram) if block_given?
    end

    initializer "zorram.validate_configuration" do
      config.after_initialize do
        unless config.zorram.valid?
          errors = config.zorram.errors.full_messages
          raise "Invalid Zorram configuration: #{errors.join(', ')}"
        end
      end
    end
  end
end
