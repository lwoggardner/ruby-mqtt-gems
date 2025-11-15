# frozen_string_literal: true

require_relative '../packet'
require 'mqtt/core/packet/subscribe'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 SUBSCRIBE packet
      #
      # Sent by client to subscribe to one or more topic filters.
      #
      # @see Core::Client#subscribe
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718063 MQTT 3.1.1 Spec §3.8
      class Subscribe
        include Packet

        fixed(8, [:reserved, 4, 0b0010])

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier for matching with SUBACK (managed automatically by session)

        # @!parse
        #   class TopicFilter
        #     # @!attribute [r] topic_filter
        #     #   @return [String<UTF8>] topic filter pattern
        #     # @!attribute [r] requested_qos
        #     #   @return [Integer] maximum QoS level accepted by the client: 0, 1, or 2
        #   end

        # @!attribute [r] topic_filters
        #   @return [Array<TopicFilter>] list of topic filters to subscribe to

        variable(packet_identifier: :int16)
        payload(
          topic_filters: list(
            :topic_filter,
            topic_filter: :utf8string,
            subscription_options: flags(
              [:reserved, 6],
              [:requested_qos, 2]
            )
          ) do
            alias_method :max_qos, :requested_qos
          end
        )

        MAX_QOS_FIELD = :requested_qos
        include MQTT::Core::Packet::Subscribe
      end
    end
  end
end
