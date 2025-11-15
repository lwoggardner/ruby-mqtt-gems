# frozen_string_literal: true

require_relative '../packet'
require 'mqtt/core/packet/subscribe'

module MQTT
  module V5
    module Packet
      # MQTT 5.0 SUBSCRIBE packet
      #
      # Sent by client to subscribe to one or more topic filters.
      #
      # @see Core::Client#subscribe
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901161 MQTT 5.0 Spec §3.8
      class Subscribe
        include Packet

        fixed(8, [:reserved, 4, 0b0010])

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier for matching with SUBACK (managed automatically by session)

        # @!group Properties

        # @!attribute [r] subscription_identifier
        #   @return [Integer] identifier for this subscription
        # @!attribute [r] user_properties
        #   @return [Array<String, String>] user-defined properties as key-value pairs

        # @!endgroup

        # @!parse
        #   class TopicFilter
        #     # @!attribute [r] topic_filter
        #     #   @return [String<UTF8>] topic filter pattern
        #     # @!attribute [r] max_qos
        #     #   @return [Integer] maximum QoS level accepted by the client: 0, 1, or 2
        #     # @!attribute [r] no_local
        #     #   @return [Boolean] do not forward messages back to same client id
        #     # @!attribute [r] retain_as_published
        #     #   @return [Boolean] retain flag from PUBLISH should be preserved
        #     # @!attribute [r] retain
        #     #   @return [Integer]
        #     #   retained message handling
        #     #
        #     #   - `0` Send retained messages at the time of subscribe
        #     #   - `1` Send retained messages only if subscription does not currently exist
        #     #   - `2` Do not send retained messages at the time of subscribe
        #   end

        # @!attribute [r] topic_filters
        #   @return [Array<TopicFilter>] list of topic filters to subscribe to

        variable(
          packet_identifier: :int16,
          properties:
        )
        payload(
          topic_filters: list(
            :topic_filter,
            topic_filter: :utf8string,
            subscription_options: flags(
              [:reserved, 2],
              [:retain, 2],
              :retain_as_published,
              :no_local,
              [:max_qos, 2]
            )
          ) do
            alias_method :requested_qos, :max_qos
          end
        )

        MAX_QOS_FIELD = :max_qos
        include MQTT::Core::Packet::Subscribe

        def match?(publish_packet)
          if subscription_identifier&.positive?
            publish_packet.match_subscription_identifier?(subscription_identifier)
          else
            super
          end
        end
      end
    end
  end
end
