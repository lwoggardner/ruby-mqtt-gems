# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 PUBREL packet
      #
      # QoS 2 publish release (part 2) sent by client in response to a PUBREC packet.
      #
      # @see Core::Client#publish
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901141 MQTT 5.0 Spec §3.6
      class PubRel
        include Packet

        fixed(6, [:reserved, 4, 0b0010])

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the PUBREC packet (receive only)

        # @!parse include ReasonCodeAck
        # @!attribute [r] reason_code
        #   acknowledgement status
        #
        #   ✅ Success:
        #
        #   - `0x00` Success
        #
        #   ❌ Error:
        #
        #   - `0x92` Packet Identifier not found
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
