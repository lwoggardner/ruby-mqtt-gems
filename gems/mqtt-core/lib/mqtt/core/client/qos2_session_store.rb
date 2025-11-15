# frozen_string_literal: true

require_relative 'session_store'
module MQTT
  module Core
    class Client
      # Session store that supports QoS 1/2 messages
      # @abstract
      class Qos2SessionStore < SessionStore
        class SessionNotRecoverable < Error; end

        def max_qos
          2
        end

        # Initialise recovery of the persistent session.
        # @!method qos2_recover
        # @raise SessionNotRecoverable if there are unhandled QOS2 messages not explicitly marked to retry
        # @return [Array<Integer>] list of QOS 2 packets ids waiting for PUBREL

        # Load the unhandled QoS 1 and 2 PUBLISH packets that should be re-delivered for this session
        # @!method qos_unhandled_packets(&deserializer)
        # @return [Hash<Packet,String>] map of deserialized packets to their unique session id

        # Persist a received QoS 1/2 packet
        # @!method store_qos_received(packet, unique_id)

        # Check if a QoS2 PUBLISH packet has previously been received
        # @!method qos2_published?(packet_id)
        #  @param [Integer] packet_id
        #  @return [Boolean] true if this packet_id was already received but is still waiting for PUBREL.

        # Release a received packet id (before we send PUBCOMP)
        # @!method qos2_release(packet_id)

        # Mark the received packet as handled from the client application perspective
        # @!method qos_handled(packet, unique_id)

        # Mark a previously received QOS1/2 packet as handled
        # @!method qos_handled(packet, unique_id)
        #   @return [void]
      end
    end
  end
end
