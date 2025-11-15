# frozen_string_literal: true

require_relative '../packet'
module MQTT
  module V5
    module Packet
      # MQTT 5.0 UNSUBACK packet
      #
      # Unsubscribe acknowledgement sent by broker in response to an UNSUBSCRIBE packet.
      #
      # @see Core::Client::Subscription#unsubscribe
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901187 MQTT 5.0 Spec §3.11
      class UnsubAck
        include Packet

        fixed(11)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier matching the UNSUBSCRIBE packet (receive only)

        # @!group Properties

        # @!attribute [r] reason_string
        #   @return [String<UTF8>] human-readable reason for the response
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs

        # @!endgroup

        # @!parse include ReasonCodeListAck
        # @!attribute [r] reason_codes
        #   acknowledgement status for each topic filter
        #
        #   ✅ Success:
        #
        #   - `0x00` Success
        #   - `0x11` No subscription existed
        #
        #   ❌ Error:
        #
        #   - `0x80` Unspecified error
        #   - `0x83` Implementation specific error
        #   - `0x87` Not authorized
        #   - `0x8F` Topic Filter invalid
        #   - `0x91` Packet Identifier in use
        #
        #   @return [Array<ReasonCode>]

        variable(
          packet_identifier: :int16,
          properties:
        )
        payload(
          reason_codes: # automatically includes ReasonCodeListAck
        )
      end
    end
  end
end
