# frozen_string_literal: true

module Zorram
  class Model
    include Attributes::DSL

    class_attribute :attributes_expires_in, instance_accessor: false, default: nil
  end
end
