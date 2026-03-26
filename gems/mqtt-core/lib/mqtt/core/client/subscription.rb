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
      # Base subscription for handling received messages
      class Subscription
        # Logic for filter matching
        module Filters
          module_function

          # @return [[Array<String>,Array<String>]] fully qualified topics list, wildcard filters list
          def partition_filters(filters = topic_filters)
            filters.partition { |f| !wildcard_filter?(f) }
          end

          # @return [Array<String>] wildcard filters for this subscription
          def wildcard_filters(filters = topic_filters)
            filters.select { |f| wildcard_filter?(f) }
          end

          # Check if a topic matches any of this subscription's filters
          # called: from qos_published
          #  - applying persistent session messages that arrived before the sub could be re-established
          # @param topic [String] topic name to match
          # @return [Boolean] true if topic matches any filter
          def match_topic?(topic, filters = topic_filters)
            fq, wc = partition_filters(filters)

            fq.include?(topic) || wc.any? { |wt| wildcard_match?(topic, wt) }
          end

          def wildcard_filter?(filter)
            filter.match?(/[+#]/)
          end

          def wildcard_match?(topic, wc_topic)
            wc_parts = wc_topic.split('/')
            topic_parts = topic.split('/')

            wc_parts.zip(topic_parts).all? do |(wc, t)|
              return true if wc == '#'
              return false if t.nil?

              wc == '+' || t == wc
            end && (wc_parts.last == '#' || topic_parts.size == wc_parts.size)
          end
        end

        include Filters

        attr_reader :topic_filters

        def initialize(client:, handler:)
          @client = client
          @handler = handler
          @topic_filters = Set.new
        end

        # Add topic filters to this Subscription and send them to the broker
        #
        # @overload subscribe(*topic_filters, **subscribe)
        #  @param topic_filters [Array<String>] filters to add
        #  @param subscribe [Hash] additional `SUBSCRIBE` packet options
        # @return [Packet::Subscribe,Packet::SubAck]
        def subscribe(*topic_filters, **)
          new_filters = nil
          client.subscribe!(*topic_filters, **) do |subscribe|
            new_filters = client.message_router.register(subscription: self, subscribe:)
          end
        rescue StandardError
          # Only purely new filters are unsubscribed on error. Previously subscribed filters are left untouched
          unsubscribe(*new_filters) if new_filters&.any?
          raise
        end

        # Subtract filters from this Subscription
        #
        # This will result in an UNSUBSCRIBE to the broker only if the requested filters are not in used by any other
        # Subscriptions.
        #
        # @param filters [Array<String>] specific filters to remove (default: all)
        # @param unsubscribe [Hash] additional properties for the `UNSUBSCRIBE` packet
        # @return [Packet::Unsubscribe, Packet::UnSubAck] if any filters were actually unsubscribed
        # @return nil if no filters were inactive
        def unsubscribe(*filters, **unsubscribe)
          filters += unsubscribe.delete(:topic_filters) || []
          inactive = client.message_router.deregister(*filters, subscription: self)
          client.unsubscribe!(*inactive, **unsubscribe) if inactive.any?
        ensure
          put(nil) if topic_filters.empty?
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
        # called from a client when a message has arrived
        def put(packet)
          handle(packet, &handler) unless packet.is_a?(StandardError)
        end

        private

        attr_reader :client, :handler

        def handle(packet)
          (block_given? ? yield(packet) : packet).tap { client.handled!(packet) if packet&.qos&.positive? }
        end
      end
    end
  end
end
