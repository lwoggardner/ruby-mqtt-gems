# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 CONNACK packet
      #
      # Connection acknowledgement sent by broker in response to a CONNECT packet.
      #
      # @see Core::Client#connect
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901074 MQTT 5.0 Spec §3.2
      class Connack
        include Packet

        fixed(2)

        # @!attribute [r] session_present
        #   @return [Boolean] whether the broker has a stored session for this client

        #   - `0x80` Unspecified error
        #   - `0x81` Malformed Packet
        #   - `0x82` Protocol Error
        #   - `0x83` Implementation specific error
        #   - `0x84` Unsupported Protocol Version
        #   - `0x85` Client Identifier not valid
        #   - `0x86` Bad User Name or Password
        #   - `0x87` Not authorized
        #   - `0x88` Server unavailable
        #   - `0x89` Server busy
        #   - `0x8A` Banned
        #   - `0x8C` Bad authentication method
        #   - `0x90` Topic Name invalid
        #   - `0x95` Packet too large
        #   - `0x97` Quota exceeded
        #   - `0x99` Payload format invalid
        #   - `0x9A` Retain not supported
        #   - `0x9B` QoS not supported
        #   - `0x9C` Use another server
        #   - `0x9F` Connection rate exceeded
        #
        #   @return [ReasonCode]

        # @!group Properties

        # @!attribute [r] session_expiry_interval
        #   @return [Integer] session expiry interval in seconds
        # @!attribute [r] receive_maximum
        #   @return [Integer] maximum number of QoS 1 and 2 messages the server will process concurrently
        # @!attribute [r] maximum_qos
        #   @return [Integer] maximum QoS level supported by the server
        # @!attribute [r] retain_available
        #   @return [Boolean] whether the server supports retained messages
        # @!attribute [r] maximum_packet_size
        #   @return [Integer] maximum packet size the server is willing to accept
        # @!attribute [r] assigned_client_identifier
        #   @return [String<UTF8>] client identifier assigned by the server
        # @!attribute [r] topic_alias_maximum
        #   @return [Integer] maximum topic alias value supported by the server
        # @!attribute [r] reason_string
        #   @return [String<UTF8>] human-readable reason for the response
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs
        # @!attribute [r] wildcard_subscription_available
        #   @return [Boolean] whether the server supports wildcard subscriptions
        # @!attribute [r] subscription_identifier_available
        #   @return [Boolean] whether the server supports subscription identifiers
        # @!attribute [r] shared_subscription_available
        #   @return [Boolean] whether the server supports shared subscriptions
        # @!attribute [r] server_keep_alive
        #   @return [Integer] keep alive time in seconds assigned by the server
        # @!attribute [r] response_information
        #   @return [String<UTF8>] response information for request/response
        # @!attribute [r] server_reference
        #   @return [String<UTF8>] server reference for redirection
        # @!attribute [r] authentication_method
        #   @return [String<UTF8>] authentication method name
        # @!attribute [r] authentication_data
        #   @return [String<Binary>] authentication data

        # @!endgroup

        variable(
          flags: flags([:reserved, 7], [:session_present, 1]),
          reason_code:, # automatically includes ReasonCodeAck
          properties:
        )

        alias connect_reason_code reason_code # align with spec naming
        alias session_present? session_present

        # Check if subscription identifiers are supported
        # @return [Boolean] true if supported (default true if not specified)
        def subscription_identifiers_available?
          subscription_identifiers_available.nil? || subscription_identifiers_available
        end

        # @!visibility private
        def defaults
          super.merge!(session_present: false)
        end
      end
    end
  end
end
