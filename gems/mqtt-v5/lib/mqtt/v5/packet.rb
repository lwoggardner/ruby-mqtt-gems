# frozen_string_literal: true

require 'mqtt/core/packet'
require_relative 'version'
require_relative 'errors'
require_relative 'packet/reason_code'

module MQTT
  module V5
    # MQTT 5.0 base packet definition
    #
    # Inherited constants (referenced via self:: in {MQTT::Core::Packet}
    module Packet
      VALUE_TYPES = {
        utf8string: MQTT::Core::Type::UTF8String,
        binary: MQTT::Core::Type::Binary,
        remaining: MQTT::Core::Type::Remaining,
        utf8pair: MQTT::Core::Type::UTF8StringPair,
        int8: MQTT::Core::Type::Int8,
        int16: MQTT::Core::Type::Int16,
        int32: MQTT::Core::Type::Int32,
        intvar: MQTT::Core::Type::VarInt,
        varint: MQTT::Core::Type::VarInt,
        boolean: MQTT::Core::Type::BooleanByte
      }.freeze

      # Available property types for MQTT version 5.0
      # @note :user_properties
      #   The spec uses the singular 'user_property' - but it is the only property that can occur more than once
      #   and it the key in the pair can itself appear more than once, so we represent it as Array<String,String>
      #   and give it the plural name

      # Attributes stored as a list of properties
      PROPERTY_TYPES = [
        [0x01, :payload_format_indicator, :int8, %i[publish will]],
        [0x02, :message_expiry_interval, :int32, %i[publish will]],
        [0x03, :content_type, :utf8string, %i[publish will]],
        [0x08, :response_topic, :utf8string, %i[publish will]],
        [0x09, :correlation_data, :binary, %i[publish will]],
        # @!attribute [r] subscription_identifier
        #   @return [Integer] (publish)
        #   @return [Array<Integer>] (subscribe)
        [0x0B, :subscription_identifier, :varint, %i[subscribe]],
        [0x08, :subscription_identifiers, [:varint], %i[publish]], # this is only sent by servers
        [0x11, :session_expiry_interval, :int32, %i[connect connack disconnect]],
        [0x12, :assigned_client_identifier, :utf8string, [:connack]],
        [0x13, :server_keep_alive, :int16, [:connack]],
        [0x15, :authentication_method, :utf8string, %i[connect connack auth]],
        [0x16, :authentication_data, :binary, %i[connect connack auth]],
        [0x17, :request_problem_information, :boolean, [:connect]],
        [0x18, :will_delay_interval, :int32, [:will]],
        [0x19, :request_response_information, :boolean, [:connect]],
        [0x1A, :response_information, :utf8string, [:connack]],
        [0x1C, :server_reference, :utf8string, %i[connack disconnect]],
        [0x1F, :reason_string, :utf8string, %i[connack puback pubrec pubrel pubcomp suback unsuback disconnect auth]],
        [0x21, :receive_maximum, :int16, %i[connect connack]],
        [0x22, :topic_alias_maximum, :int16, %i[connect connack]],
        [0x23, :topic_alias, :int16, [:publish]],
        [0x24, :maximum_qos, :int8, [:connack]],
        [0x25, :retain_available, :boolean, [:connack]],
        # @!attribute [r] user_properties
        #   @return [Array<String,String>] list of key,value pairs, same key may appear more than once
        [0x26, :user_properties, [:utf8pair], :all],
        [0x27, :maximum_packet_size, :int32, %i[connect connack]],
        [0x28, :wildcard_subscription_available, :boolean, [:connack]],
        [0x29, :subscription_identifier_available, :boolean, [:connack]],
        [0x2A, :shared_subscription_available, :boolean, [:connack]]
      ].map { |data| MQTT::Core::Type::Properties::PropertyType.create(*data, types: VALUE_TYPES) }.freeze

      # If the sender is compliant with this specification it will not send Malformed Packets or cause Protocol Errors

      # Reason codes
      REASON_CODES = [
        [0x00, 'Success', %i[connack puback pubrec pubrel pubcomp unsuback auth]],
        [0x00, 'Normal disconnection', %i[disconnect]],
        [0x00, 'Granted QoS 0', %i[suback]],
        [0x01, 'Granted QoS 1', %i[suback]],
        [0x02, 'Granted QoS 2', %i[suback]],
        [0x04, 'Disconnect with Will Message', %i[disconnect]],
        [0x10, 'No matching subscribers', %i[puback pubrec]],
        [0x11, 'No subscription existed', %i[unsuback]],
        [0x18, 'Continue authentication', %i[auth]],
        [0x19, 'Re-authenticate', %i[auth]],
        [0x80, 'Unspecified error', %i[connack puback pubrec suback unsuback disconnect], true],
        [0x81, 'Malformed Packet', %i[connack disconnect]],
        [0x82, 'Protocol Error', %i[connack disconnect]],
        [0x83, 'Implementation specific error', %i[connack puback pubrec suback unsuback disconnect], true],
        [0x84, 'Unsupported Protocol Version', %i[connack]],
        [0x85, 'Client Identifier not valid', %i[connack]],
        [0x86, 'Bad User Name or Password', %i[connack]],
        [0x87, 'Not authorized', %i[connack puback pubrec suback unsuback disconnect]],
        [0x88, 'Server unavailable', %i[connack], true],
        [0x89, 'Server busy', %i[connack disconnect], true],
        [0x8A, 'Banned', %i[connack]],
        [0x8B, 'Server shutting down', %i[disconnect], true],
        [0x8C, 'Bad authentication method', %i[connack disconnect]],
        [0x8D, 'Keep alive timeout', %i[disconnect], true],
        [0x8E, 'Session taken over', %i[disconnect]],
        [0x8F, 'Topic Filter invalid', %i[suback unsuback disconnect]],
        [0x90, 'Topic Name invalid', %i[connack puback pubrec disconnect]],
        [0x91, 'Packet Identifier in use', %i[puback pubrec suback unsuback]],
        [0x92, 'Packet Identifier not found', %i[pubrel pubcomp]],
        [0x93, 'Receive Maximum exceeded', %i[disconnect], true],
        [0x94, 'Topic Alias invalid', %i[disconnect]],
        [0x95, 'Packet too large', %i[connack disconnect]],
        [0x96, 'Message rate too high', %i[disconnect], true],
        [0x97, 'Quota exceeded', %i[connack puback pubrec suback disconnect]],
        [0x98, 'Administrative action', %i[disconnect]],
        [0x99, 'Payload format invalid', %i[connack puback pubrec disconnect]],
        [0x9A, 'Retain not supported', %i[connack disconnect]],
        [0x9B, 'QoS not supported', %i[connack disconnect]],
        [0x9C, 'Use another server', %i[connack disconnect]],
        [0x9E, 'Shared Subscriptions not supported', %i[suback disconnect]],
        [0x9F, 'Connection rate exceeded', %i[connack disconnect], true],
        [0xA0, 'Maximum connect time', %i[disconnect]],
        [0xA1, 'Subscription Identifiers not supported', %i[suback disconnect]],
        [0xA2, 'Wildcard Subscriptions not supported', %i[suback disconnect]]
      ].freeze.tap { |codes| codes.each { |code| ReasonCode.register(*code) } }

      # rubocop:disable Style/MutableConstant
      PACKET_TYPES = {}
      # rubocop:enable Style/MutableConstant

      # Additional class methods for the packet
      module Definition
        def reason_code
          include ReasonCodeAck
          { type: :int8, default: 0x00 }
        end

        def reason_codes
          include ReasonCodeListAck
          list(:int8)
        end
      end

      extend MQTT::Core::Packet::ModuleMethods

      def self.included(mod)
        mod.include(MQTT::Core::Packet)
        mod.extend(Definition)
      end
    end
  end
end
