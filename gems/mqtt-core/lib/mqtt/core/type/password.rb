# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # Password data - input can be a proc to pull a password
      # converts to String with binary encoding
      module Password
        module_function

        # return [String with binary encoding]
        def read(io)
          size = io.read(2)&.unpack1('S>')
          io.read(size)
        end

        def write(value, io)
          value ||= default_value
          io.write([value.size, value].pack('S>A*'))
        end

        # @return [String(binary)]
        def from(value, **)
          return nil if value.nil?

          value = value.call if value.respond_to?(:call)
          value.to_s.b
        end

        def default_value
          @default_value ||= ''.b.freeze
        end
      end
    end
  end
end
