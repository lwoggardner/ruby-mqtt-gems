# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # Properties Map (used since MQTT 5.0)
      class Properties
        # @!parse class PropertyType < Data; end
        PropertyType = Data.define(:id, :name, :type, :packet_types) do
          class << self
            def create(id, name, type, packet_types = :all, types: {})
              new(id, name, resolve_type(type, types), packet_types)
            end

            def resolve_type(input_type, types)
              case input_type
              when Symbol
                types.fetch(input_type) { raise ProtocolError, "Unknown property type #{input_type}" }
              when Array
                List.new(resolve_type(input_type.first, types))
              else
                input_type
              end
            end
          end

          def initialize(id:, name:, type:, packet_types: [:all])
            super
          end

          def from(value)
            type.from(value)
          end

          def read(io, into)
            if type.is_a?(Type::List)
              (into[name] ||= []) << type.item_type.read(io)
            else
              into[name] = type.read(io)
            end
          end

          def write(value, io, write_type: type)
            if write_type.is_a?(Type::List)
              value.each { |item| write(item, io, write_type: type.item_type) }
            else
              VarInt.write(id, io)
              write_type.write(value, io)
            end
          end

          def for_packet?(packet_type_name)
            return true if packet_types == :all

            packet_types.include?(packet_type_name)
          end
        end

        def initialize(packet_type_name, property_types)
          @property_types = property_types.select { |pt| pt.for_packet?(packet_type_name) }.freeze
          @property_map =
            Hash.new { |_h, k| raise ProtocolError, "Unknown property type #{k} for #{packet_type_name}" }
                .merge!(@property_types.to_h { |pt| [pt.name, pt] })
                .merge!(@property_types.to_h { |pt| [pt.id, pt] })
                .freeze
        end

        def sub_properties
          @property_types.to_h { |pt| [pt.name, pt.type] }
        end

        def read(io)
          default_value.tap do |output|
            # Where properties is the last thing in a packet and there are no properties, the length property
            # is not required to be set
            next if io.eof?

            Packet.read_sio(io) do |sio|
              until sio.eof?
                id = VarInt.read(sio)
                property_type = @property_map.fetch(id) do
                  raise ProtocolError, format('Unknown property id 0x%02x', id)
                end
                property_type.read(sio, output)
              end
            end
          end
        end

        def write(values, io)
          Packet.write_sio(io) do |sio|
            values.each_pair do |name, value|
              property_type = @property_map.fetch(name) { raise ProtocolError, "Unknown property name #{name}" }
              property_type.write(value, sio)
            end
          end
        end

        # @param [Hash|nil] values
        def from(values, data:)
          values ||= default_value
          raise ArgumentError 'Properties values must be a Hash' unless values.respond_to?(:each_pair)

          # properties with entries at the top level of the data structure override the underlying hash value
          @property_types.filter_map do |property_type|
            property_type.name.tap { |name| values[name] = data.delete(name) if data.key?(name) }
          end

          # now make sure every entry in values is valid and converted to type
          values.filter_map do |(name, value)|
            property_type = @property_map.fetch(name) { raise ArgumentError, "Unknown property name #{name}" }
            next nil unless (filled_value = property_type.from(value))

            [name, filled_value]
          end.to_h.freeze
        end

        def default_value
          {}
        end
      end
    end
  end
end
