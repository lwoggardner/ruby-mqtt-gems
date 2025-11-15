# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 PUBCOMP packet
      #
      # QoS 2 publish complete (part 3) sent by broker in response to a PUBREL packet.
      #
      # @see Core::Client#publish
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901151 MQTT 5.0 Spec §3.7
      class PubComp
        include Packet

        fixed(7)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the PUBREL packet (receive only)

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
