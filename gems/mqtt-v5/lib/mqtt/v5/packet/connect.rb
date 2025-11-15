# frozen_string_literal: true

require_relative '../packet'
require_relative '../version'
require 'mqtt/core/packet/connect'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 CONNECT packet
      #
      # Sent by client to establish connection with the broker.
      #
      # @see Core::Client#connect
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901033 MQTT 5.0 Spec §3.1
      class Connect
        include Packet
        include Core::Packet::Connect

        # Avoid name clashes between sub-properties
        def self.sub_property_method(name, property_name)
          case name
          when :will_properties
            return :will_user_properties if property_name == :user_properties
          end
          property_name
        end

        fixed(1)

        # @!attribute [r] protocol_name
        #   @return [String<UTF8>] protocol name (managed automatically)
        # @!attribute [r] protocol_version
        #   @return [Integer] protocol version (managed automatically)
        # @!attribute [r] clean_start
        #   @return [Boolean] if true server will abandon any stored session (managed automatically from session store)
        # @!attribute [r] will_qos
        #   @return [Integer] QoS level for the Will message: 0, 1, or 2 (default 0)
        # @!attribute [r] will_retain
        #   @return [Boolean] should the Will message be retained (default false)
        # @!attribute [r] keep_alive
        #   @return [Integer] maximum duration in seconds between packets sent by the client (default 60)

        # @!group Properties

        # @!attribute [r] session_expiry_interval
        #   @return [Integer] session expiry interval in seconds (managed automatically from session store)
        # @!attribute [r] receive_maximum
        #   @return [Integer] maximum number of QoS 1 and 2 messages the client will process concurrently
        # @!attribute [r] maximum_packet_size
        #   @return [Integer] maximum packet size the client is willing to accept
        # @!attribute [r] topic_alias_maximum
        #   @return [Integer] maximum topic alias value the client accepts
        # @!attribute [r] request_response_information
        #   @return [Boolean] whether the client requests response information
        # @!attribute [r] request_problem_information
        #   @return [Boolean] whether the client requests problem information
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs
        # @!attribute [r] authentication_method
        #   @return [String<UTF8>] authentication method name
        # @!attribute [r] authentication_data
        #   @return [String<Binary>] authentication data

        # @!endgroup

        # @!attribute [r] client_id
        #   @return [String<UTF8>] client identifier string (managed from session store, default '')
        # @!attribute [r] will_topic
        #   @return [String<UTF8>] topic name to send the Will message to
        # @!attribute [r] will_payload
        #   @return [String<Binary>] payload of the Will message
        # @!attribute [r] will_properties
        #   @return [Hash<Symbol>] properties for the Will message
        # @!attribute [r] username
        #   @return [String<UTF8>] username for authenticating with the server
        # @!attribute [r] password
        #   @return [String<Binary>] password for authenticating with the server

        variable(
          protocol_name: :utf8string,
          protocol_version: :int8,
          connect_flags: flags(
            :username_flag, :password_flag,
            :will_retain,
            [:will_qos, 2],
            :will_flag,
            :clean_start,
            :reserved
          ),
          keep_alive: :int16,
          properties: properties(:connect)
        )

        payload(
          client_id: :utf8string,
          will_properties: { type: properties(:will), if: :will_flag },
          will_topic: { type: :utf8string, if: :will_flag },
          will_payload: { type: :binary, if:  :will_flag },
          username: { type: :utf8string, if:  :username },
          password: { type: :binary, if: :password }
        )

        alias clean_requested? clean_start
        alias username? :username_flag
        alias password? :password_flag
        alias will_flag? :will_flag

        # @!visibility private
        def defaults
          super.merge!(client_id: '', keep_alive: 60, will_retain: false, will_qos: 0, clean_start: false)
        end

        # @!visibility private
        def apply_overrides(data)
          super
          data.merge!(
            protocol_name: 'MQTT',
            protocol_version: PROTOCOL_VERSION
          )
        end

        # @!visibility private
        def success!(connack)
          connack.success!
        end
      end
    end
  end
end
