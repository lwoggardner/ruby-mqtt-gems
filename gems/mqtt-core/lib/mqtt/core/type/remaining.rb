# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # remaining payload, no length prefix, reads to EOF (StringIO) and writes the whole value as binary
      # string
      module Remaining
        module_function

        def read(io)
          # read to end of file (which only works because it is only ever used with a StringIO
          io.read
        end

        def write(value, io)
          io.write(value.to_s.b)
        end

        def from(value, **)
          value.to_s
        end

        def default_value
          ''.b
        end
      end
    end
  end
end
