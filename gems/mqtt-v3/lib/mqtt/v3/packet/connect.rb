# frozen_string_literal: true

require_relative '../packet'
require 'mqtt/core/packet/connect'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 CONNECT packet
      #
      # Sent by client to establish connection with the broker.
      #
      # @see Core::Client#connect
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718028 MQTT 3.1.1 Spec §3.1
      class Connect
        include Packet
        include Core::Packet::Connect

        fixed(1)

        # @!attribute [r] protocol_name
        #   @return [String<UTF8>] protocol name (managed automatically)
        # @!attribute [r] protocol_version
        #   @return [Integer] protocol version (managed automatically)
        # @!attribute [r] clean_session
        #   @return [Boolean] if true server will abandon any stored session (managed automatically from session store)
        # @!attribute [r] will_qos
        #   @return [Integer] QoS level for the Will message: 0, 1, or 2 (default 0)
        # @!attribute [r] will_retain
        #   @return [Boolean] should the Will message be retained (default false)
        # @!attribute [r] keep_alive
        #   @return [Integer] maximum duration in seconds between packets sent by the client (default 60)

        # @!attribute [r] client_id
        #   @return [String<UTF8>] client identifier string (auto-assigned if empty with non-zero session expiry)
        # @!attribute [r] will_topic
        #   @return [String<UTF8>] topic name to send the Will message to
        # @!attribute [r] will_payload
        #   @return [String<Binary>] payload of the Will message
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
            :clean_session,
            :reserved
          ),
          keep_alive: :int16
        )

        payload(
          client_id: :utf8string,
          will_topic: { type: :utf8string, if: :will_flag },
          will_payload: { type: :binary, if:  :will_flag },
          username: { type: :utf8string, if:  :username },
          password: { type: :binary, if: :password }
        )

        alias clean_requested? clean_session
        alias username? :username_flag
        alias password? :password_flag
        alias will_flag? :will_flag

        # @!visibility private
        def defaults
          super.merge!(client_id: nil, keep_alive: 60, clean_session: true, will_qos: 0, will_retain: false)
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
