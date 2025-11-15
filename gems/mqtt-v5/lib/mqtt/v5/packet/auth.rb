# frozen_string_literal: true

require_relative '../packet'
module MQTT
  module V5
    module Packet
      # MQTT 5.0 AUTH packet
      #
      # Sent by client or broker for extended authentication exchange.
      #
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901217 MQTT 5.0 Spec §3.15
      class Auth
        include Packet

        fixed(15)

        # @!parse include ReasonCodeAck
        # @!attribute [r] reason_code
        #   authentication status
        #
        #   ✅ Success:
        #
        #   - `0x00` Success
        #   - `0x18` Continue authentication
        #   - `0x19` Re-authenticate
        #
        #   @return [ReasonCode]

        # @!group Properties

        # @!attribute [r] authentication_method
        #   @return [String<UTF8>] authentication method name
        # @!attribute [r] authentication_data
        #   @return [String<Binary>] authentication data
        # @!attribute [r] reason_string
        #   @return [String<UTF8>] human-readable reason for the response
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs

        # @!endgroup

        variable(
          reason_code:, # automatically includes ReasonCodeAck
          properties:
        )

        # @return [self] if reason code is 0x18 (Continue authentication)
        # @raise [ProtocolError] if reason code is not 0x18
        def continue!
          return self if reason_code == 0x18

          raise ProtocolError, reason_code, 'expected reason code 0x18 (auth continue)'
        end
      end
    end
  end
end
