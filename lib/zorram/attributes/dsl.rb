# frozen_string_literal: true

module Zorram
  module Attributes
    module DSL
      def self.included(base)
        base.include(ActiveModel::API)
        base.include(ActiveModel::Attributes)
        base.include(Kredis::Attributes)

        base.extend(ClassMethods)

        base.include(InstanceMethods)
      end

      module ClassMethods
        # Generate Redis table name based on class namespace
        def table_name
          @table_name ||= name.split("::").drop(1).map(&:tableize).join(":")
        end

        # Configure TTL for the kredis hash key storing attributes.
        # Accepts Integer seconds (e.g., 3600) or ActiveSupport::Duration (e.g., 7.days).
        def expires_in(value)
          self.attributes_expires_in = value&.to_i.presence
        end

        # Create a new record and apply provided attributes at creation time
        def create!(**attrs)
          id = generate_next_id
          record = new(id:)
          record.send(:setup_record_for_creation, attrs)
          record
        end

        # Same as create!, but without raising (behavior matches ActiveRecord API)
        def create(**attrs)
          create!(**attrs)
        end

        def find(id)
          record = new(id: id.to_i)
          record.send(:load_from_storage!)
          record
        end

        private

        def generate_next_id
          Kredis.redis.incr("#{table_name}:next_id")
        end
      end

      module InstanceMethods # rubocop:disable Metrics/ModuleLength
        def save # rubocop:disable Naming/PredicateMethod
          persist!
          true
        end

        def update!(**attrs)
          ensure_storage_exists!
          attrs = sanitize_update_attributes(attrs)

          assign_known_attributes(attrs)
          persist!

          handle_single_attribute_update_return(attrs)
        end

        def update(**attrs)
          update!(**attrs)
        end

        private

        # === Storage Management ===

        def setup_record_for_creation(attrs)
          ensure_attributes_hash_alias!
          initialize_storage!
          assign_known_attributes(attrs)
          persist!
        end

        def load_from_storage!
          ensure_attributes_hash_alias!
          data = storage.to_h

          raise_not_found_error if data.blank?

          assign_stored_attributes(data)
        end

        def ensure_storage_exists!
          return if storage_exists?

          raise Zorram::Exceptions::StorageExpiredError,
                "Cannot update #{self.class.name}##{id}: storage expired or not found"
        end

        def storage_exists?
          redis_connection { |redis| redis.exists(storage.key) }.to_i.positive?
        end

        def initialize_storage!
          redis_connection do |redis|
            redis.hset(storage.key, "__created_at", Time.current.to_i.to_s)
            apply_ttl_if_configured(redis)
          end
        end

        # === Redis Connection Management ===

        def redis_connection
          @__zorram_redis ||= create_redis_connection
          yield @__zorram_redis
        end

        def create_redis_connection
          require_redis_gem
          ::Redis.new(url: redis_url)
        end

        def require_redis_gem
          require "redis"
        rescue LoadError
          raise "Redis client is not available. Ensure the 'redis' gem is installed."
        end

        def redis_url
          ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")
        end

        # === Attributes Management ===

        def ensure_attributes_hash_alias!
          return if attributes_alias_configured?
          return unless kredis_attributes_method_exists?

          setup_attributes_alias
        end

        def attributes_alias_configured?
          @__attributes_alias_done
        end

        def kredis_attributes_method_exists?
          return false unless respond_to?(:attributes)

          kredis_candidate = safely_call_attributes_method
          kredis_candidate.is_a?(Kredis::Types::Hash)
        end

        def safely_call_attributes_method
          attributes
        rescue StandardError
          nil
        end

        def setup_attributes_alias
          alias_kredis_store_reader
          redefine_attributes_reader
          @__attributes_alias_done = true
        end

        def alias_kredis_store_reader
          singleton_class.alias_method :attributes_store, :attributes
        end

        def redefine_attributes_reader
          instance = self
          singleton_class.define_method(:attributes) do
            build_activemodel_attributes_hash(instance)
          end
        end

        def build_activemodel_attributes_hash(instance)
          instance.class.attribute_types.keys.each_with_object({}) do |name, hash|
            hash[name.to_s] = instance.public_send(name)
          end
        end

        def storage
          ensure_attributes_hash_alias!

          return attributes_store if respond_to?(:attributes_store)

          find_kredis_storage || raise_storage_error
        end

        def find_kredis_storage
          val = safely_call_attributes_method
          val if val.is_a?(Kredis::Types::Hash)
        end

        def raise_storage_error
          raise "Kredis storage for :attributes is not available"
        end

        # === Persistence ===

        def persist!
          validate_aasm_state_attributes!
          persist_attributes_to_storage
          apply_ttl_after_persistence
        end

        def persist_attributes_to_storage
          attribute_values.each { |k, v| storage[k] = v&.to_s if v }
        end

        def apply_ttl_after_persistence
          ttl = self.class.attributes_expires_in
          return unless ttl.to_i.positive?

          redis_connection { |redis| redis.expire(storage.key, ttl) }
        end

        def apply_ttl_if_configured(redis)
          ttl = self.class.attributes_expires_in
          return unless ttl.to_i.positive?

          redis.expire(storage.key, ttl)
        end

        # === Attribute Assignment ===

        def assign_known_attributes(attrs)
          return if attrs.blank?

          attrs.each { |k, v| safe_assign_attribute(k, v) }
        end

        def assign_stored_attributes(data)
          allowed_attributes = self.class.attribute_types.keys.map(&:to_s)

          data.slice(*allowed_attributes).each do |k, v|
            public_send("#{k}=", v)
          end
        end

        def safe_assign_attribute(name, value)
          setter = "#{name}="
          return unless respond_to?(setter)

          if aasm_managed_attribute?(name)
            assign_aasm_attribute(name, value, setter)
          else
            public_send(setter, value)
          end
        end

        def assign_aasm_attribute(name, value, setter)
          validate_aasm_value(name, value) if value.present?
          public_send(setter, value&.to_s)
        end

        def validate_aasm_value(name, value)
          machine = aasm_machine_for(name.to_sym)
          return unless machine

          str = value.to_s
          allowed_states = extract_allowed_states(machine)

          return if allowed_states.include?(str)

          raise ArgumentError, "Invalid #{name} '#{str}'. Allowed: #{allowed_states.join(', ')}"
        end

        def attribute_values
          self.class.attribute_types.keys.each_with_object({}) do |name, hash|
            next if name.to_sym == :id

            hash[name] = public_send(name)
          end
        end

        # === AASM Integration ===

        def aasm_managed_attribute?(name)
          aasm_machine_names.include?(name.to_sym)
        end

        def validate_aasm_state_attributes!
          return unless aasm_available?

          aasm_machine_names.each do |machine_name|
            validate_machine_state(machine_name)
          end
        end

        def validate_machine_state(machine_name)
          return unless respond_to?(machine_name)

          machine = aasm_machine_for(machine_name)
          return unless machine

          current_value = public_send(machine_name)&.to_s
          return if current_value.blank?

          validate_current_state(machine_name, current_value, machine)
        end

        def validate_current_state(machine_name, current_value, machine)
          allowed_states = extract_allowed_states(machine)
          return if allowed_states.include?(current_value)

          raise ArgumentError, "Invalid #{machine_name} '#{current_value}'. Allowed: #{allowed_states.join(', ')}"
        end

        def aasm_machine_for(name)
          return nil unless aasm_available?

          machine = safely_get_aasm_machine(name)
          return nil unless valid_aasm_machine?(machine, name)

          machine
        end

        def safely_get_aasm_machine(name)
          self.class.aasm(name)
        rescue StandardError
          nil
        end

        def valid_aasm_machine?(machine, name)
          return false unless machine.respond_to?(:states)
          return false if machine_has_no_states?(machine)

          machine_targets_attribute?(machine, name)
        end

        def machine_has_no_states?(machine)
          states = machine.states
          states.respond_to?(:empty?) && states.empty?
        end

        def machine_targets_attribute?(machine, name)
          attribute_from_machine(machine)&.to_sym == name.to_sym
        end

        def attribute_from_machine(machine)
          return machine.attribute_name if machine.respond_to?(:attribute_name)
          return machine.config[:column] if machine.respond_to?(:config) &&
                                            machine.config.is_a?(Hash) &&
                                            machine.config[:column]

          nil
        end

        def extract_allowed_states(machine)
          machine.states.map { |state| state.name.to_s }
        end

        def aasm_machine_names
          return [] unless aasm_available?

          @aasm_machine_names ||= discover_aasm_machine_names
        end

        def discover_aasm_machine_names
          names = extract_machine_names_from_storage
          return names if names.any?

          # Fallback: probe declared attributes
          probe_attributes_for_machines
        end

        def extract_machine_names_from_storage
          storage = self.class.aasm
          return [] unless storage.respond_to?(:state_machines)

          storage.state_machines.keys
        rescue StandardError
          []
        end

        def probe_attributes_for_machines
          self.class.attribute_types.keys.map(&:to_sym).select do |name|
            aasm_machine_for(name)
          end
        end

        def aasm_available?
          self.class.respond_to?(:aasm)
        end

        # === Helper Methods ===

        def sanitize_update_attributes(attrs)
          attrs.except(:id, "id")
        end

        def handle_single_attribute_update_return(attrs)
          return self unless attrs.size == 1

          key = attrs.keys.first
          public_send(key)
        end

        def raise_not_found_error
          raise Zorram::Exceptions::NotFoundError,
                "Cannot find #{self.class.name}##{id}"
        end
      end
    end
  end
end
