# frozen_string_literal: true

require_relative '../../errors'
module MQTT
  module Core
    # Base subscription error
    class SubscriptionError < ResponseError
      # @!attribute [r] errors
      #   @return [Hash<String,ReasonCode|ResultCode] Map of topic_filter to failure code
      def initialize(failed_filters)
        msg = ["#{self::NAME} failed for #{failed_filters.size} topics"] +
              failed_filters.map { |topic_filter, status| "#{topic_filter}(#{status})" }
        super(msg.join("\n\t"))
      end
    end

    class SubscribeError < SubscriptionError
      NAME = 'Subscribe'
    end

    class UnsubscribeError < SubscriptionError
      NAME = 'Unsubscribe'
    end

    class Client
      Subscription = Data.define(:sub_packet, :ack_packet, :handler, :client)

      # Base subscription for handling received messages
      class Subscription < Data
        # @!attribute [r] sub_packet
        #   @return [Packet] the `SUBSCRIBE` packet

        # @!attribute [r] ack_packet
        #  @return [Packet] the `SUBACK` packet

        # Classify `SUBACK` results
        # @return [Hash<String,Symbol>]
        #   Map pf filter to acknowledged status. version-specific.
        #
        # @see Packet::Subscribe#filter_status
        def filter_status
          sub_packet.filter_status(ack_packet)
        end

        # Deregister this Subscription from its client and unsubscribe its topics from the server.
        # @param [Hash<Symbol>] unsubscribe additional properties for the `UNSUBSCRIBE` packet
        # @note this will also terminate the current enumeration.
        def unsubscribe(**unsubscribe)
          client.delete_subscription(self, **unsubscribe, **unsubscribe_params)
        end

        # Yield self, ensuring {#unsubscribe}
        # @return [Object] the result of the block
        def with!
          yield self
        ensure
          unsubscribe
        end

        # Yield self, returning self, ensuring {#unsubscribe}
        # @yieldreturn [void]
        # @return [self]
        def tap!(&)
          tap { with!(&) }
        end

        # @!visibility private
        # Match messages
        def ===(other)
          sub_packet === other # rubocop:disable Style/CaseEquality
        end

        # @!visibility private
        def resubscribe_topic_filters
          sub_packet.resubscribe_topic_filters(ack_packet)
        end

        # Successfully subscribed topic filters
        # @return [Array<String>]
        def subscribed_topic_filters
          sub_packet.subscribed_topic_filters(ack_packet)
        end

        # @!visibility private
        # called from a client when a message has arrived
        def put(packet)
          handle(packet, &handler) unless packet.is_a?(StandardError)
        end

        # @!visibility private
        def match?(publish_packet)
          sub_packet.match?(publish_packet)
        end

        private

        def unsubscribe_params
          sub_packet.unsubscribe_params(ack_packet)
        end

        def handle(packet)
          raise packet if packet.is_a?(StandardError)

          (block_given? ? yield(packet) : packet).tap { client.handled!(packet) if packet&.qos&.positive? }
        end
      end
    end
  end
end
