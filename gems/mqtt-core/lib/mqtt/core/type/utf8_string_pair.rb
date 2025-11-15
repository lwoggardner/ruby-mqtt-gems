# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # Key value pair as UTF8 encoded strings
      module UTF8StringPair
        module_function

        def read(io)
          [UTF8String.read(io), UTF8String.read(io)].freeze
        end

        def from(value, **)
          raise ArgumentError, 'Value must be Array<String,String>' unless value.is_a?(Array) && value.size == 2

          value.map { |v| UTF8String.from(v) }.freeze
        end

        def write(value, io)
          raise ProtocolError, 'Value must be Array<String,String>' unless value.is_a?(Array) && value.size == 2

          UTF8String.write(value[0], io)
          UTF8String.write(value[1], io)
        end
      end
    end
  end
end
