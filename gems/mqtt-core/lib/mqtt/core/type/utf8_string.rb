# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # UTF8 Encoded String written with length as prefix
      module UTF8String
        module_function

        def read(io)
          size = io.read(2)&.unpack1('S>')
          io.read(size).force_encoding(Encoding::UTF_8).tap { |s| raise EncodingError unless valid_utf8?(s) }
        end

        def from(value, **)
          return nil if value.nil?

          value = value.to_s
          return value if valid_utf8?(value)

          value.encode(Encoding::UTF_8).tap { |s| raise EncodingError unless valid_utf8?(s) }
        end

        def write(value, io)
          value ||= default_value
          io.write([value.size, value].pack('S>A*'))
        end

        def default_value
          @default_value ||= ''.encode(Encoding::UTF_8).freeze
        end

        def valid_utf8?(str)
          str.encoding == Encoding::UTF_8 && str.valid_encoding? && !str.include?("\u0000")
        end
      end
    end
  end
end
