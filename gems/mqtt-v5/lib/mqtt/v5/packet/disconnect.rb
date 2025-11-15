# frozen_string_literal: true

module MQTT
  module V5
    module Packet
      # MQTT 5.0 DISCONNECT packet
      #
      # Sent by client to gracefully disconnect, or received from broker to indicate disconnection.
      #
      # @see Core::Client#disconnect
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901205 MQTT 5.0 Spec §3.14
      class Disconnect
        include Packet

        fixed(14)

        # @!parse include ReasonCodeAck
        # @!attribute [r] reason_code
        #   disconnection reason
        #
        #   ✅ Success:
        #
        #   - `0x00` Normal disconnection
        #   - `0x04` Disconnect with Will Message
        #
        #   ❌ Error:
        #
        #   - `0x80` Unspecified error
        #   - `0x81` Malformed Packet
        #   - `0x82` Protocol Error
        #   - `0x83` Implementation specific error
        #   - `0x87` Not authorized
        #   - `0x89` Server busy
        #   - `0x8B` Server shutting down
        #   - `0x8C` Bad authentication method
        #   - `0x8D` Keep alive timeout
        #   - `0x8E` Session taken over
        #   - `0x8F` Topic Filter invalid
        #   - `0x90` Topic Name invalid
        #   - `0x93` Receive Maximum exceeded
        #   - `0x94` Topic Alias invalid
        #   - `0x95` Packet too large
        #   - `0x96` Message rate too high
        #   - `0x97` Quota exceeded
        #   - `0x98` Administrative action
        #   - `0x99` Payload format invalid
        #   - `0x9A` Retain not supported
        #   - `0x9B` QoS not supported
        #   - `0x9C` Use another server
        #   - `0x9E` Shared Subscriptions not supported
        #   - `0x9F` Connection rate exceeded
        #   - `0xA0` Maximum connect time
        #   - `0xA1` Subscription Identifiers not supported
        #   - `0xA2` Wildcard Subscriptions not supported
        #
        #   @return [ReasonCode]

        # @!group Properties

        # @!attribute [r] session_expiry_interval
        #   @return [Integer] session expiry interval in seconds
        # @!attribute [r] reason_string
        #   @return [String<UTF8>] human-readable reason for disconnection
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs
        # @!attribute [r] server_reference
        #   @return [String<UTF8>] server reference for redirection

        # @!endgroup

        variable(
          reason_code:, # automatically includes ReasonCodeAck
          properties:
        )
      end
    end
  end
end
