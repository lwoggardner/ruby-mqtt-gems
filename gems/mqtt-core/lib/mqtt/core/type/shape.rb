# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # Base module for structured MQTT types {Packet} and {SubType}
      module Shape
        Field = Data.define(:name, :type, :condition) do
          def write(obj, io)
            type.write(obj.send(name), io) if obj.instance_exec(&condition)
          end

          def read(obj, io)
            value = type.read(io) if obj.instance_exec(&condition)
            value = type.default_value if value.nil? && type.respond_to?(:default_value)
            value
          end
        end

        # methods for defining fields
        module Definition
          attr_reader :fields

          def flags(*flags)
            Type::BitFlags.new(*flags)
          end

          def list(type, **fields, &)
            if fields.any?
              klass = Class.new(Type::SubType)
              klass.instance_variable_set(
                :@fields, resolve_fields(fields).tap { |resolved| define_field_methods(resolved, klass:) }
              )
              # Define additional methods and aliases (after field methods are defined!)
              klass.class_eval(&) if block_given?
              type = const_set(type.to_s.split('_').map(&:capitalize).join, klass)
            elsif type.is_a?(Symbol)
              type = self::VALUE_TYPES[type]
            end

            Type::List.new(type)
          end

          def resolve_fields(fields)
            fields.map do |(name, type)|
              type, condition = field_type_for(type)
              Field.new(name:, type:, condition:)
            end
          end

          def field_type_for(type_info)
            return field_type_for({ type: type_info, if: true }) unless type_info.is_a?(Hash)

            type, type_if = type_info.values_at(:type, :if)
            type = self::VALUE_TYPES[type] if type.is_a?(Symbol)
            condition =
              case type_if
              when Symbol
                -> { send(type_if) }
              when Proc
                type_if
              else
                -> { true }
              end
            [type, condition]
          end

          # Avoid name clashes
          def sub_property_method(_name, property_name)
            property_name
          end

          def define_field_methods(fields, klass: self)
            fields.map do |field|
              name, type, _condition = field.deconstruct

              if type.respond_to?(:sub_properties)
                define_property_readers(name, type, klass:)
                define_hash_reader(name, type, klass:)
              else
                klass.define_method(name) { @data[name] }
              end
            end
          end

          def define_property_readers(name, type, klass:)
            type.sub_properties.each_key do |property_name|
              method = klass.sub_property_method(name, property_name) if klass.respond_to?(:sub_property_method)
              klass.define_method(method || property_name) { @data.dig(name, property_name) }
            end
          end

          def define_hash_reader(name, type, klass:)
            klass.define_method(name) do
              type.sub_properties.keys.filter_map do |property_name|
                method = klass.sub_property_method(name, property_name) if klass.respond_to?(:sub_property_method)
                value = send(method || property_name)
                [property_name, value] unless value.nil?
              end.to_h.freeze
            end
          end
        end

        def initialize(*deserialize_args, **data)
          @data = {}
          apply_data(defaults)
          if deserialize_args.any?
            deserialize(*deserialize_args)
          else
            apply_data(data) if data.any?
            apply_overrides(@data)
          end
          validate if respond_to?(:validate, true)
          @data.freeze
        end

        def serialize(io)
          serialize_fields(self.class.fields, io)
        end

        def to_h
          @data
        end

        def deconstruct_keys(*keys)
          to_h.slice(keys)
        end

        private

        # rubocop:disable Metrics/AbcSize
        def apply_data(data)
          self.class.fields.each do |f|
            # source @data (defaults)
            # data[f.name] if data.key?(f.name) - overwrites or merges with defaults
            # properties if data[sub_property_name]
            if f.type.respond_to?(:sub_properties)
              result = @data[f.name] ||= {}
              result.merge!(data.delete(f.name)) if data.key?(f.name)
              apply_sub_properties(f, result, data)
            elsif data.key?(f.name)
              @data[f.name] = f.type.from(data.delete(f.name))
            end
          end
          raise ArgumentError, "Unused data for #{self.class.name} - #{data}" unless data.empty?
        end
        # rubocop:enable Metrics/AbcSize

        def apply_sub_properties(field, result, data)
          field.type.sub_properties.each do |property_name, property_type|
            check_name =
              if self.class.respond_to?(:sub_property_method)
                self.class.sub_property_method(field.name, property_name)
              else
                property_name
              end
            result[property_name] = property_type.from(data.delete(check_name)) if data.key?(check_name)
          end
        end

        # applied in the same way as user supplied data
        def defaults
          {}
        end

        def apply_overrides(data)
          # do nothing by default
        end

        def serialize_fields(fields, io)
          fields.each { |f| f.write(self, io) }
        end

        def deserialize_fields(fields, io)
          fields.filter_map do |f|
            value = f.read(self, io)
            [f.name, value] if value
          end.to_h
        end

        def deserialize(io)
          @data.merge!(deserialize_fields(self.class.fields, io))
        end
      end
    end
  end
end
