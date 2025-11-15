# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # Variable Byte Integer
      module VarInt
        module_function

        # Maximum variable integer (hence maximum packet size = 256MB)
        MAX_INTVAR = 268_435_455

        def read(io)
          value = 0
          multiplier = 1

          loop do
            encoded_byte = io.readbyte
            return value unless encoded_byte

            value += (encoded_byte & 0x7F) * multiplier

            raise ProtocolError, 'Malformed Variable Byte Integer' if multiplier > 0x80**3

            multiplier *= 0x80

            return value if encoded_byte.nobits?(128)
          end
        end

        def from(value)
          value ||= 0
          raise ArgumentError, 'Vaiue must be Integer' unless value.respond_to?(:to_int)

          value = value.to_i
          raise ArgumentError, "Value out of range (0 - #{MAX_INTVAR})" unless value.between?(0, MAX_INTVAR)

          value
        end

        def write(value, io)
          value ||= 0
          raise ProtocolError, "Value out of range (0 - #{MAX_INTVAR})" unless value.between?(0, MAX_INTVAR)

          loop do
            encoded_byte = value % 0x80
            value /= 0x80
            encoded_byte |= 0x80 if value.positive?
            io.write([encoded_byte].pack('C'))
            break if value.zero?
          end
        end
      end
    end
  end
end
