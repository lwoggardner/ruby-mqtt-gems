# frozen_string_literal: true

require_relative '../packet'
require 'mqtt/core/packet/publish'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 PUBLISH packet
      #
      # Sent by client to publish a message to the broker, or received from broker when subscribed to a topic.
      #
      # @see Core::Client#publish
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718037 MQTT 3.1.1 Spec §3.3
      class Publish
        include Packet
        include Core::Packet::Publish

        # @!attribute [r] dup
        #   @return [Boolean] duplicate delivery flag (managed automatically by session)
        # @!attribute [r] qos
        #   @return [Integer] QoS level: 0, 1, or 2 (default 0)
        # @!attribute [r] retain
        #   @return [Boolean] retain flag (default false)

        fixed(3, :dup, [:qos, 2], :retain)

        # @!attribute [r] topic_name
        #   @return [String<UTF8>] topic name to publish to
        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier for QoS 1/2 exchanges (managed automatically by session)

        variable(
          topic_name: :utf8string,
          packet_identifier: { type: :int16, if: -> { qos.positive? } }
        )

        # @!attribute [r] payload
        #   @return [String<Binary>] message payload

        payload(payload: :remaining)

        alias topic topic_name
      end
    end
  end
end
