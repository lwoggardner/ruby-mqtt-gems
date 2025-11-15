# frozen_string_literal: true

require_relative '../errors'

module MQTT
  module V5
    module Packet
      ReasonCode = Data.define(:code, :name, :error)

      # Encapsulates reason codes
      class ReasonCode < Data
        # @!attribute [r] code
        #   @return [Integer] the reason code value
        # @!attribute [r] name
        #   @return [String] the reason code name
        # @!attribute [r] error
        #   @return [Class,nil] the error class for failed reason codes

        class << self
          # rubocop:disable Style/OptionalBooleanParameter
          def register(code, name, packet_types, retriable = false)
            @reason_codes ||= Hash.new { |h, k| h[k] = {} }
            rc = create(code, name, retriable)
            packet_types.each { |packet_type| @reason_codes[packet_type][code] = rc }
          end
          # rubocop:enable Style/OptionalBooleanParameter

          def find(packet_name, reason_code)
            @reason_codes.dig(packet_name, reason_code) || unknown_reason_code(packet_name, reason_code)
          end

          def failed?(reason_code)
            reason_code >= 0x80
            # define readers
          end

          private

          def create(code, name, retriable)
            error = define_error_class(code, name, retriable) if code >= 0x80
            new(code, name, error)
          end

          def unknown_reason_code(packet_name, reason_code)
            new(reason_code, "Unknown ReasonCode for #{packet_name}", UnknownReasonCode)
          end

          def define_error_class(code, name, retriable)
            klass = Class.new(ResponseError)
            klass.include(Error::Retriable) if retriable
            klass.instance_variable_set(:@code, code)
            MQTT::V5.const_set(name.split(/\s+/).map(&:capitalize).join, klass)
          end
        end

        def failed?
          self.class.failed?(code)
        end

        def success!(reason_string)
          return self unless failed?

          raise error, reason_string || name
        end

        def to_s
          format '%<name>s(0x%02<code>x)', name:, code:
        end
      end

      # Success/Failed for packets with a single reason_code field
      module ReasonCodeAck
        def defaults
          super.merge!({ reason_code: 0x00 })
        end

        def success?
          !failed?
        end

        # @return [self]
        # @raise [ResponseError]
        def success!
          reason_code_data.success!(reason_string) && self
        end

        def failed?
          ReasonCode.failed?(reason_code)
        end

        def to_s
          "#{super}: #{reason_code_data}"
        end

        def reason_code_data
          ReasonCode.find(packet_name, reason_code)
        end
      end

      # Module for packets with a :reason_codes field
      module ReasonCodeListAck
        def reason_codes_data
          reason_codes.map { |rc| ReasonCode.find(packet_name, rc) }
        end

        def to_s
          "#{super}: #{reason_codes_data.map { |rc| format('0x%02<code>x', code: rc.code) }.tally}"
        end
      end
    end
  end
end
