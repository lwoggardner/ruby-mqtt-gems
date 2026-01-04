# frozen_string_literal: true

require 'mqtt/core/client'
require_relative 'packets'
require_relative 'client/authenticator'
require_relative 'client/connection'
require_relative 'client/session'
require_relative 'client/request_response'
require_relative 'client/json_rpc'

module MQTT
  module V5
    # An MQTT::V5 Client
    #
    class Client < Core::Client
      # @!visibility private
      def self.packet_module
        Packet
      end

      # @!visibility private
      def self.protocol_version
        5
      end

      include RequestResponse
      include JsonRpc

      # @return [TopicAlias::Manager] the topic alias manager manages the bi-directional mapping of topic names to
      #   topic aliases to limit bandwidth usage.
      attr_reader :topic_aliases

      # @!visibility private
      def self.new_options(configure_opts)
        { topic_aliases: configure_opts.delete(:topic_aliases) }
      end

      # @!visibility private
      def initialize(topic_aliases: nil, **)
        @topic_aliases = topic_aliases
        super(**)
      end

      # V5 Authentication flow (untested)
      def reauthenticate(**auth)
        connection.reauthenticate(**auth) { |packet| send_and_wait(packet) { |ack| handle_ack(packet, ack) } }
      end

      # @!method publish(topic, message, **publish)
      #   @param [String] topic
      #   @param [String] message
      #   @param [Hash<Symbol>] publish additional attributes for the `PUBLISH` packet.
      #   @option publish [Boolean] topic_alias (true) whether to try to assign a topic alias. See {#topic_aliases}
      #
      #     This property is a hint to the {TopicAlias::Manager}. The primary use is to avoid aliasing
      #     a topic that will only be used once, or to indicate that this is the last publish to a topic, and thus
      #     leave room in the alias cache for other topics.
      #
      #     If you pass an Integer, it is treated as `true` if positive otherwise `false`.
      #     The value is not used directly.
      #   @return [self]
      #   @see Packet::Publish
      #   @see Core::Client#publish
    end
  end
end
