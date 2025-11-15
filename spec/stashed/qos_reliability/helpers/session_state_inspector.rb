# frozen_string_literal: true

module MQTT
  module QoSReliability
    # Session State Inspector - Inspects session state
    class SessionStateInspector
      attr_reader :session_store

      def initialize(session_store)
        @session_store = session_store
      end

      # Verify that a packet with the given ID is stored in the session
      # Returns true if the packet is found
      def verify_packet_stored(packet_id)
        # This is a simplified implementation that assumes the session store
        # has a method to check if a packet is stored
        # The actual implementation would depend on the session store's API
        if session_store.respond_to?(:packet_stored?)
          session_store.packet_stored?(packet_id)
        else
          # For stores that don't expose this API, we can try to infer it
          # from the list of packet IDs
          list_packet_ids.include?(packet_id)
        end
      end

      # Verify that a packet with the given ID is not stored in the session
      # Returns true if the packet is not found
      def verify_packet_deleted(packet_id)
        !verify_packet_stored(packet_id)
      end

      # Verify the QoS 2 state for a packet
      # Expected states: :pubrec_sent, :pubrel_received, :pubcomp_sent
      # Returns true if the packet is in the expected state
      def verify_qos2_state(packet_id, expected_state)
        # This is a simplified implementation that assumes the session store
        # has a method to check the QoS 2 state of a packet
        # The actual implementation would depend on the session store's API
        if session_store.respond_to?(:qos2_state)
          session_store.qos2_state(packet_id) == expected_state
        else
          # For stores that don't expose this API, we can't verify the state
          # and would need to rely on other verification methods
          puts "Warning: Cannot verify QoS 2 state for packet #{packet_id}"
          false
        end
      end

      # Count the number of packets stored in the session
      # Returns the count of stored packets
      def count_stored_packets
        # This is a simplified implementation that assumes the session store
        # has a method to count stored packets
        # The actual implementation would depend on the session store's API
        if session_store.respond_to?(:packet_count)
          session_store.packet_count
        else
          # For stores that don't expose this API, we can try to infer it
          # from the list of packet IDs
          list_packet_ids.size
        end
      end

      # List the packet IDs stored in the session
      # Returns an array of packet IDs
      def list_packet_ids
        # This is a simplified implementation that assumes the session store
        # has a method to list packet IDs
        # The actual implementation would depend on the session store's API
        if session_store.respond_to?(:packet_ids)
          session_store.packet_ids
        else
          # For stores that don't expose this API, we can't list the packet IDs
          # and would need to rely on other verification methods
          puts "Warning: Cannot list packet IDs from session store"
          []
        end
      end

      # Verify that the session is clean (no stored packets)
      # Returns true if the session is clean
      def verify_session_clean
        count_stored_packets.zero?
      end
    end
  end
end