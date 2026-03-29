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
        # @return [Array<Integer>] list of QOS 2 packet ids waiting for PUBREL

        # Mark a QoS2 packet id as pending (received, awaiting PUBREL)
        # @!method qos2_pending(packet_id)

        # Release a received QoS2 packet id (before we send PUBCOMP)
        # @!method qos2_release(packet_id)
      end
    end
  end
end
