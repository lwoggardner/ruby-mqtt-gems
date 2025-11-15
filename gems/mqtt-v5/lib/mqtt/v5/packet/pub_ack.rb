# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 PUBACK packet
      #
      # QoS 1 acknowledgement sent by broker in response to a PUBLISH packet.
      #
      # @see Core::Client#publish
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901121 MQTT 5.0 Spec §3.4
      class PubAck
        include Packet

        fixed(4)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the PUBLISH packet (receive only)

        # @!parse include ReasonCodeAck
        # @!attribute [r] reason_code
        #   acknowledgement status
        #
        #   ✅ Success:
        #
        #   - `0x00` Success
        #   - `0x10` No matching subscribers
        #
        #   ❌ Error:
        #
        #   - `0x80` Unspecified error
        #   - `0x83` Implementation specific error
        #   - `0x87` Not authorized
        #   - `0x90` Topic Name invalid
        #   - `0x91` Packet Identifier in use
        #   - `0x97` Quota exceeded
        #   - `0x99` Payload format invalid
        #
        #   @return [ReasonCode]

        # @!group Properties

        # @!attribute [r] reason_string
        #   @return [String<UTF8>] human-readable reason for the response
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs

        # @!endgroup

        variable(
          packet_identifier: :int16,
          reason_code:, # automatically includes ReasonCodeAck
          properties:
        )
      end
    end
  end
end
