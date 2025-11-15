# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V3
    class ConnectionRefused < MQTT::V3::ResponseError; end

    module Packet
      # MQTT 3.1.1 CONNACK packet
      #
      # Connection acknowledgement sent by broker in response to a CONNECT packet.
      #
      # @see Core::Client#connect
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718033 MQTT 3.1.1 Spec §3.2
      class Connack
        include Packet

        fixed(2)

        # @!attribute [r] session_present
        #   @return [Boolean] whether the broker has a stored session for this client

        # @!attribute [r] return_code
        #   @return [Integer] connection return code:
        #
        #   - `0x00` Connection accepted
        #   - `0x01` Unacceptable protocol version
        #   - `0x02` Identifier rejected
        #   - `0x03` Server unavailable
        #   - `0x04` Bad user name or password
        #   - `0x05` Not authorized

        variable(
          flags: flags([:reserved, 7], [:session_present, 1]),
          return_code: :int8
        )

        RETURN_CODES = {
          0x00 => :success,
          0x01 => :unacceptable_protocol_version,
          0x02 => :identifier_rejected,
          0x03 => :server_unavailable,
          0x04 => :bad_user_name_or_password,
          0x05 => :not_authorized
        }.freeze

        def success!
          return self if success?

          raise ConnectionRefused, RETURN_CODES.fetch(return_code, :unknown_error)
        end

        def success?
          return_code.zero?
        end

        def failed?
          !success?
        end

        alias connect_return_code return_code # align with spec naming
        alias session_present? session_present

        # @!visibility private
        def defaults
          super.merge!(session_present: false, return_code: 0x00)
        end
      end
    end
  end
end
