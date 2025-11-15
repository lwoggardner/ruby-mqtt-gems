# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # unsigned integers of fixed bit size
      class FixedInt
        def initialize(bitsize, pack)
          @bitsize = bitsize
          @pack = pack
        end

        def read(io)
          io.read(@bitsize / 8)&.unpack1(@pack)
        end

        def from(value, **)
          return value.to_i if value.respond_to?(:to_i)

          value ? 1 : 0
        end

        def write(value, io)
          value = from(value)
          raise ProtocolError, "Value '#{value}' out of range" unless value.between?(0, (2**@bitsize) - 1)

          io.write([value].pack(@pack))
        end

        def default_value
          0
        end
      end

      # 8 bit unsigned integer
      Int8 = FixedInt.new(8, 'C')
      # 16 bit unsigned integer
      Int16 = FixedInt.new(16, 'S>')
      # 32 bit unsigned integer
      Int32 = FixedInt.new(32, 'L>')
    end
  end
end
