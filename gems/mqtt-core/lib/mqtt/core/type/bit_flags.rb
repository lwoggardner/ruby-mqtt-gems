# frozen_string_literal: true

require_relative '../../errors'
require_relative 'fixed_int'

module MQTT
  module Core
    module Type
      # Booleans and small integers encoded in a single byte
      class BitFlags
        def initialize(*flags)
          @flags = flags.map { |f| f.is_a?(Array) ? f : [f, 1] }
          raise ProtocolError, 'Total bits must be 8' unless @flags.sum { |(_, bitsize)| bitsize } == 8
        end

        attr_reader :flags

        def sub_properties
          @sub_properties ||=
            @flags.filter_map do |(name, bitsize, *)|
              [name, bitsize == 1 ? BooleanByte : Int8] unless name == :reserved
            end.to_h
        end

        # rubocop:disable Metrics/AbcSize

        # @param [Integer,IO] io can be a previously readbyte or an IO to read the byte from
        # @return [Hash<Symbol, Integer|Boolean>]
        def read(io)
          flags_byte = io.is_a?(Integer) ? io : Int8.read(io)

          flags.reverse.filter_map do |(flag, bitsize, reserved)|
            mask = (1 << bitsize) - 1
            flag_value = (flags_byte & mask)
            raise ProtocolError if flag == :reserved && flag_value != (reserved || 0)

            # If bitsize is one, flag is a Boolean,  otherwise leave as Integer
            flag_value = (flag_value == 1) if bitsize == 1
            flags_byte >>= bitsize
            [flag, flag_value] unless flag == :reserved
          end.to_h
        end

        def from(input_value)
          input_value ||= 0
          input_value = read(input_value) if input_value.is_a?(Integer)

          flags.each do |(flag_name, bitsize)|
            next if flag_name == :reserved

            # convert to int and validate
            input_value[flag_name] = to_int(input_value[flag_name], bitsize, exception_class: ArgumentError)
            # convert to boolean if bitsize is 1
            input_value[flag_name] = (input_value[flag_name] == 1) if bitsize == 1
          end

          # Reject unknown flags
          invalid = input_value.keys.reject { |k| sub_properties.include?(k) }

          return input_value if invalid.empty?

          raise ArgumentError, "Unknown bitflags #{invalid}, expected only #{sub_properties}"
        end
        # rubocop:enable Metrics/AbcSize

        def write(values, io)
          output_byte = 0
          flags.each do |(property_name, bitsize, reserved)|
            output_byte <<= bitsize
            output_byte += to_int(values.fetch(property_name, reserved || 0), bitsize, exception_class: ProtocolError)
          end
          Int8.write(output_byte, io)
        end

        def to_int(value, bitsize, exception_class:)
          if value.is_a?(Integer)
            return value if value.between?(0, (1 << bitsize) - 1)

            raise exception_class, "Invalid bitflag value #{value} for bitsize #{bitsize}"
          elsif bitsize == 1
            value ? 1 : 0
          else
            raise exception_class, "Invalid bitflag value #{value}"
          end
        end
      end
    end
  end
end
