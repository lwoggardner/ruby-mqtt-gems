# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 SUBACK packet
      #
      # Subscription acknowledgement sent by broker in response to a SUBSCRIBE packet.
      #
      # @see Core::Client#subscribe
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901171 MQTT 5.0 Spec §3.9
      class SubAck
        include Packet

        fixed(9)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the SUBSCRIBE packet (receive only)

        # @!group Properties

        # @!attribute [r] reason_string
        #   @return [String<UTF8>] human-readable reason for the response
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs

        # @!endgroup

        # @!parse include ReasonCodeListAck
        # @!attribute [r] reason_codes
        #   acknowledgement status for each subscription
        #
        #   ✅ Success:
        #
        #   - `0x00` Granted QoS 0
        #   - `0x01` Granted QoS 1
        #   - `0x02` Granted QoS 2
        #
        #   ❌ Error:
        #
        #   - `0x80` Unspecified error
        #   - `0x83` Implementation specific error
        #   - `0x87` Not authorized
        #   - `0x8F` Topic Filter invalid
        #   - `0x91` Packet Identifier in use
        #   - `0x97` Quota exceeded
        #   - `0xA1` Subscription Identifiers not supported
        #   - `0xA2` Wildcard Subscriptions not supported
        #
        #   @return [Array<ReasonCode>]

        variable(
          packet_identifier: :int16,
          properties:
        )
        payload(
          reason_codes: # automatically includes ReasonCodeListAck
        )

        alias return_codes reason_codes
      end
    end
  end
end
