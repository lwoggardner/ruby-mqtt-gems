# frozen_string_literal: true

module MQTT
  module Core
    class Client
      # Birth-phase message buffering and QoS2 protocol-level deduplication for a Session
      module QosTracker
        def qos_initialize
          @birth_complete = false
          @birth_buffer = []

          # QoS2 protocol dedup - only manipulated from the 'receive' thread
          @qos2_pending = Set.new
          @qos2_pending.merge(session_store.qos2_recover) if session_store.max_qos == 2
        end

        # Have we already received a QOS2 packet with this packet id?
        def qos2_published?(id)
          return true unless @qos2_pending.add?(id)

          session_store.qos2_pending(id) if session_store.max_qos == 2
          false
        end

        # Release the pending qos2 packet (return true if we had previously seen it)
        # rubocop:disable Naming/PredicateMethod
        def qos2_release(id)
          session_store.qos2_release(id)
          !!@qos2_pending.delete?(id)
        end
        # rubocop:enable Naming/PredicateMethod

        # Buffer a received packet during the birth phase for later replay to subscriptions
        def birth_buffer(packet)
          synchronize { @birth_buffer << packet unless @birth_complete }
        end

        # Replay buffered packets to a new subscription during the birth phase
        # @yield [packet] for each buffered packet
        def qos_subscribed(&)
          return if @birth_complete

          synchronize do
            return if @birth_complete

            @birth_buffer.each(&)
          end
        end

        # Complete the birth phase and clear the buffer
        def birth_complete!
          synchronize do
            @birth_complete = true
            @birth_buffer.clear
          end
        end

        # @return [Boolean] True if the birth phase is complete
        def birth_complete?
          @birth_complete || synchronize { @birth_complete }
        end
      end
    end
  end
end
