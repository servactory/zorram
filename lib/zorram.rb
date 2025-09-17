# frozen_string_literal: true

require "kredis"

require "zorram/support/loader"

module Zorram
end

require "zorram/engine" if defined?(Rails::Engine)
