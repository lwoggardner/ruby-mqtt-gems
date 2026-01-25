# frozen_string_literal: true

module MQTT
  module Core
    class Client
      # Modules for tracking received QOS packets in a Session
      module QosTracker
        def qos_initialize
          @birth_complete = false

          # This is only manipulated from the 'receive' thread, does not require synchronisation
          @qos2_pending = Set.new
          @qos2_pending.merge(session_store.qos2_recover) if session_store.max_qos == 2

          # QOS packets - count down tracking
          @qos_packets = {}
          qos_load { |io| deserialize(io) } if session_store.max_qos.positive?
        end

        # Have we already received a QOS2 packet with this packet id?
        def qos2_published?(id)
          !@qos2_pending.add?(id)
        end

        # Called when a QOS1/2 PUBLISH arrives from the server and has been matched against available subscriptions
        def qos_received(packet, subs)
          if birth_complete? && subs.zero?
            log.warn("No subscription for #{packet.topic_name}")
            return
          end

          pkt_info = { unique_id: format('%013d', Time.now.to_f * 1000), counter: subs, subscribed: subs.positive? }
          session_store.store_qos_received(packet, pkt_info[:unique_id])
          synchronize { @qos_packets[packet] = pkt_info }
        end

        # Release the pending qos2 packet (return true if we had previously seen it)
        # rubocop:disable Naming/PredicateMethod
        def qos2_release(id)
          session_store.qos2_release(id)
          !!@qos2_pending.delete?(id)
        end
        # rubocop:enable Naming/PredicateMethod

        # Called when a new subscription arrives.
        # @return [Array<PUBLISH>] a list of matching packets to enqueue on the subscription.
        def qos_subscribed(&matcher)
          return [] if @birth_complete

          synchronize do
            return if @birth_complete

            @qos_packets.filter_map do |packet, data|
              next false unless matcher.call(packet)

              data[:counter] += 1
              data[:subscribed] = true
              packet
            end
          end
        end

        # Called when topics are explicitly unsubscribed
        def qos_unsubscribed(&matcher)
          return if @birth_complete

          synchronize do
            return if @birth_complete

            @qos_packets.delete_if { |packet, data| !data[:subscribed] && matcher.call(packet) }
          end
        end

        # Called when a Subscription completes handling of a QoS1/2 message.
        def handled!(packet)
          unique_id = synchronize do
            counter = (@qos_packets[packet][:counter] -= 1)
            return unless counter.zero? && @birth_complete

            @qos_packets.delete(packet)[:unique_id]
          end

          session_store.qos_handled(packet, unique_id)
        end

        # Complete the birth phase and process all pending zero-counter messages
        def birth_complete!
          handled = synchronize do
            @birth_complete = true

            @qos_packets.select { |_pkt, data| data[:counter].zero? }.tap do |handled|
              handled.each do |pkt, data|
                log.warn("No subscription for #{pkt.topic_name}") unless data[:subscribed]
                @qos_packets.delete(pkt)
              end
            end
          end

          handled.each { |(packet, data)| session_store.qos_handled(packet, data[:unique_id]) }
        end

        # @return [Boolean] True if the birth phase is complete
        def birth_complete?
          @birth_complete || synchronize { @birth_complete }
        end

        private

        attr_reader :qos_packets

        # These are unhandled QoS 1/2 packets, mapped to their unique id (timestamps)
        # @return [Array<Packet>] the list of unhandled packets to send to subscriptions as they connect
        def qos_load(&)
          @qos_packets.merge!(session_store.qos_unhandled_packets(&).transform_values do |v|
            { unique_id: v, counter: 0 }
          end)
        end
      end
    end
  end
end
