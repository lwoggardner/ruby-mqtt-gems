# frozen_string_literal: true

require_relative '../packet'
require 'mqtt/core/packet/unsubscribe'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 UNSUBSCRIBE packet
      #
      # Sent by client to unsubscribe from one or more topic filters.
      #
      # @see Core::Client::Subscription#unsubscribe
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718072 MQTT 3.1.1 Spec §3.10
      class Unsubscribe
        include Packet
        include Core::Packet::Unsubscribe

        fixed(10, [:reserved, 4, 0b0010])

        # @!attribute [r] packet_identifier
        #   @return [Integer] packet identifier for matching with UNSUBACK (managed automatically by session)

        # @!attribute [r] topic_filters
        #   @return [Array<String<UTF8>>] list of topic filters to unsubscribe from

        variable(packet_identifier: :int16)
        payload(topic_filters: list(:utf8string))

        def unsubscribed_topic_filters(_unsuback = nil)
          topic_filters
        end

        # @!visibility private
        def success!(_unsuback)
          self
        end
      end
    end
  end
end
