# frozen_string_literal: true

require_relative 'fixed_int'

module MQTT
  module Core
    module Type
      # A type that resolves to a reason code
      class ReasonCodes
        # @!parse class ReasonCode < ::Data; end
        ReasonCode = Data.define(:code, :name, :packet_types, :error) do
          def for_packet?(packet_type_name)
            code == 0xff || packet_types.include?(packet_type_name)
          end

          def success?
            !failed?
          end

          def failed?
            code >= 0x80
          end

          def to_s
            format '%<name>s(0x%02<code>x)', name:, code:
          end
        end

        def initialize(valid_codes)
          @reason_code_map = valid_codes.to_h { |rc| [rc.code, rc] }
        end

        def fetch(...)
          @reason_code_map.fetch(...)
        end

        def read(io)
          # if (s)io is at eof then the reason code is assumed to be success
          fetch(Int8.read(io) || 0x00) { |rc| raise ProtocolError, "Invalid Reason Code #{rc}" }
        end

        def write(value, io)
          # use from here as sometimes the code is applied as a default
          Int8.write(from(value).code, io)
        end

        def from(input_value, **)
          input_value = input_value.code if input_value.is_a?(ReasonCode)
          raise ArgumentError, "Invalid Reason Code #{input_value}" unless input_value.respond_to?(:to_i)

          fetch(input_value.to_i) { |rc| raise ArgumentError, "Invalid Reason Code #{rc}" }
        end

        def default_value
          fetch(0x00)
        end
      end
    end
  end
end
