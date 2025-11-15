# frozen_string_literal: true

require 'mqtt/core/packet'
require_relative '../errors'
require_relative 'type/shape'
require_relative 'type/sub_type'
require_relative 'type/utf8_string'
require_relative 'type/utf8_string_pair'
require_relative 'type/binary'
require_relative 'type/fixed_int'
require_relative 'type/var_int'
require_relative 'type/boolean_byte'
require_relative 'type/remaining'
require_relative 'type/properties'
require_relative 'type/bit_flags'
require_relative 'type/reason_codes'
require_relative 'type/list'
require 'stringio'

module MQTT
  module Core
    # Version agnostic packet structure
    module Packet
      # Class Methods for defining packet structures (and substructures)
      module Definition
        include Type::Shape::Definition

        attr_reader :fixed_fields, :variable_fields, :payload_fields, :packet_type

        # Flags in the fixed header
        def fixed(packet_type, *flags)
          self::PACKET_TYPES[packet_type] = self
          self::PACKET_TYPES[packet_name] = self
          flags = [[:reserved, 4]] if flags.empty?
          flags.unshift([:packet_type, 4])
          @packet_type = packet_type
          @packet_name = packet_name
          fields = { fixed_flags: Type::BitFlags.new(*flags) }
          @fixed_fields = resolve_fields(fields).tap { |resolved| define_field_methods(resolved) }
          @variable_fields = []
          @payload_fields = []
        end

        def packet_name
          name.split('::').last.downcase.to_sym
        end

        # Fields in the variable header
        def variable(**fields)
          @variable_fields = resolve_fields(fields).tap { |resolved| define_field_methods(resolved) }
        end

        # Payload structure
        def payload(**fields)
          @payload_fields =  resolve_fields(fields).tap { |resolved| define_field_methods(resolved) }
        end

        def properties(packet_name = self.packet_name)
          Type::Properties.new(packet_name, self::PROPERTY_TYPES)
        end

        # for Shape#apply_data
        def fields
          @fixed_fields + @variable_fields + @payload_fields
        end
      end

      # Methods to be extended into specific version module methods
      module ModuleMethods
        def deserialize(io)
          return nil unless (header_byte = io.getbyte)

          packet(header_byte >> 4).new(header_byte, io)
        end

        def packet(packet_name)
          self::PACKET_TYPES.fetch(packet_name) { raise ProtocolError, "Unknown packet id or name #{packet_name}" }
        end

        def build_packet(packet_name, **packet_data)
          packet(packet_name).new(**packet_data)
        end
      end

      def self.included(mod)
        mod.extend Definition
      end

      include Type::Shape

      def apply_overrides(data)
        data[:fixed_flags] ||= {}
        data[:fixed_flags][:packet_type] = self.class.packet_type
        super
      end

      def packet_type
        self.class.packet_type
      end

      def packet_name
        self.class.packet_name
      end

      def id
        return nil if packet_identifier&.zero?

        packet_identifier
      end

      def to_s
        @to_s ||=
          begin
            parts = [self.class.name]
            parts << "(#{id})" if respond_to?(:packet_identifier) && id
            parts.join
          end
      end

      def serialize(io)
        serialize_fields(self.class.fixed_fields, io)

        Packet.write_sio(io) do |sio|
          serialize_fields(self.class.variable_fields, sio)
          serialize_fields(self.class.payload_fields, sio)
        end
        # io.flush
        self
      end

      def deserialize(header_byte, io)
        @data.merge!(deserialize_fields(self.class.fixed_fields, header_byte))
        Packet.read_sio(io) do |sio|
          @data.merge!(deserialize_fields(self.class.variable_fields, sio))
          @data.merge!(deserialize_fields(self.class.payload_fields, sio))
        end
      end

      class << self
        def read_sio(io, &)
          length = Type::VarInt.read(io)
          return unless length
          raise ProtocolError, "Cannot read negative length #{length}" if length.negative?
          return if length.zero?

          StringIO.new.binmode
                  .tap { |sio| length -= IO.copy_stream(io, sio, length) while length.positive? }
                  .tap(&:rewind)
                  .tap(&)
        rescue EOFError
          raise ProtocolError, "Packet length #{length} exceeds available data"
        end

        def write_sio(io, &)
          StringIO.new.binmode.tap(&).tap(&:rewind).tap do |sio|
            Type::VarInt.write(sio.size, io)
            IO.copy_stream(sio, io)
          end
        end

        # debugging/testing do not log
        def hex(payload)
          payload.bytes.map { |byte| format('%02x', byte) }.join(' ')
        end
      end
    end
  end
end
