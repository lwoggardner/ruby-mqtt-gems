# frozen_string_literal: true

require_relative '../packet'
require 'mqtt/core/packet/publish'
require_relative 'payload'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 PUBLISH packet
      #
      # Sent by client to publish a message to the broker, or received from broker when subscribed to a topic.
      #
      # @see Client#publish
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901100 MQTT 5.0 Spec §3.3
      class Publish
        include Packet
        include Core::Packet::Publish
        include Payload

        # @!attribute [r] dup
        #   @return [Boolean] duplicate delivery flag (managed automatically by session)
        # @!attribute [r] qos
        #   @return [Integer] QoS level: 0, 1, or 2 (default 0)
        # @!attribute [r] retain
        #   @return [Boolean] should this message be retained by the broker (default false)
        fixed(3, :dup, [:qos, 2], :retain)

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier for QoS 1/2 exchanges (managed automatically by session)

        # @!group Properties

        # @!attribute [r] payload_format_indicator
        #  @return [Integer] 0 = unspecified binary, 1 = UTF-8 (managed automatically from payload encoding)
        #  @see Payload#apply_payload_encoding

        # @!attribute [r] content_type
        #  @return [String<UTF8>] application indicator of payload content (managed automatically from payload encoding)
        #  @see Payload#apply_payload_encoding

        # @!attribute [r] message_expiry_interval
        #   @return [Integer] message expiry interval in seconds

        # @!attribute [r] response_topic
        #   @return [String<UTF8>] topic name for response messages

        # @!attribute [r] correlation_data
        #   @return [String<Binary>] correlation data for request/response

        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs

        # @!attribute [r] subscription_identifiers
        #   @return [Array<Integer>] subscription identifiers (receive only, set by broker)

        variable(
          topic_name: :utf8string,
          packet_identifier: { type: :int16, if: -> { qos.positive? } },
          properties:
        )

        # @!visibility private
        alias orig_topic_alias topic_alias

        # @!attribute [r] topic_alias
        # Managed automatically by {TopicAlias::Manager}. See {Client#publish}.
        # @return [Integer|nil] the assigned topic alias id
        def topic_alias
          (@alias_info && @alias_info[:alias]) || orig_topic_alias
        end

        # @!endgroup

        # @return [Boolean] whether {TopicAlias::Manager} will try to assign an outgoing {#topic_alias}
        # @see Client#publish
        def assign_alias?
          @assign_alias
        end

        # @!visibility private
        attr_reader :alias_info

        # @!visibility private
        alias orig_topic_name topic_name

        # @!attribute [r] topic_name
        # @return [String<UTF8>] topic name to publish to
        def topic_name
          (@alias_info && @alias_info[:name]) || orig_topic_name
        end

        alias topic topic_name

        # @!attribute [r] payload
        #  The message content (frozen)
        #
        #  For incoming packets the {Payload#force_payload_encoding encoding} of the payload is
        #  automatically inferred from {payload_format_indicator} and {content_type}.
        #  @return [String]
        payload(payload: :remaining)

        # @!visibility private
        def apply_alias(alias: nil, name: nil)
          @alias_info = { alias:, name: }
        end

        # @!visibility private
        # Check if this packet matches a subscription identifier
        # @param [Integer] sub_id subscription identifier to check
        # @return [Boolean]
        def match_subscription_identifier?(sub_id)
          (subscription_identifiers || []).include?(sub_id)
        end

        # @!visibility private
        def apply_data(data)
          @assign_alias = data.delete(:assign_alias) if data.key?(:assign_alias)
          super
        end

        # @!visibility private
        def apply_overrides(data)
          super

          apply_payload_encoding(data[:properties] ||= {}, payload.encoding) if payload
        end

        # @!visibility private
        def deserialize(header_byte, io)
          super

          force_payload_encoding(payload, payload_format_indicator, content_type)
        end

        # Attributes provided to {Core::Client::EnumerableSubscription}
        MESSAGE_ATTRIBUTES =
          %i[qos retain message_expiry_interval response_topic correlation_data content_type user_properties].freeze

        # Provides packet as topic, payload and a map of attributes (See {MESSAGE_ATTRIBUTES})
        # @yield [topic,payload,**attributes]
        # @return [[String, String, Hash]] topic, payload, **attributes when no block given
        # @return [Object] block result when block given
        def deconstruct_message(&)
          super(*MESSAGE_ATTRIBUTES, &)
        end

        # @!visibility private
        def validate
          super
          raise ArgumentError, 'Response topic cannot contain wildcards' if response_topic&.match?(/[#+]/)
        end
      end
    end
  end
end
