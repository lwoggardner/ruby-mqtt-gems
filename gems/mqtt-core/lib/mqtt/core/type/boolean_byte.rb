# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # If we are reading or writing a boolean byte then it will exist
      # but if it does not exist then it is assumed to be true
      module BooleanByte
        module_function

        # rubocop:disable Naming/PredicateMethod
        def read(io)
          int_value = Int8.read(io)
          raise ProtocolError, 'Value must be 0 or 1' unless int_value.between?(0, 1)

          !int_value.zero?
        end
        # rubocop:enable Naming/PredicateMethod

        def write(value, io)
          value = 1 if value.nil?
          value = value ? 1 : 0 unless value.is_a?(Integer)
          raise ProtocolError, 'Value must be 0 or 1' unless value.between?(0, 1)

          io.write([value].pack('C'))
        end

        # param [Integer,Object, nil] value
        #   for integers anything non-zero is considered true
        #   everything else uses ruby truthiness
        #   nil is considered true
        # @return [Boolean]
        def from(value, **)
          return nil if value.nil?
          return !value.zero? if value.is_a?(Integer)

          !!value
        end

        # rubocop:disable Naming/PredicateMethod
        def default_value
          false
        end
        # rubocop:enable Naming/PredicateMethod
      end
    end
  end
end
