# frozen_string_literal: true

require_relative 'qos2_session_store'
require 'concurrent_monitor'

module MQTT
  module Core
    class Client
      # A Session Store held in memory for the duration of this process only
      # Supports QoS 2 to recover from network errors but cannot recover from a crash
      class MemorySessionStore < Qos2SessionStore
        # @!visibility private
        # Allow server-assigned client ids (and anonymous sessions in MQTT 3)
        attr_writer :client_id

        def initialize(expiry_interval: nil, client_id: '')
          super
          @clean = true
          # outgoing packet store, waiting for ACK
          @store = {}
        end

        def connected!
          @expiry_timeout = ConcurrentMonitor::TimeoutClock.new(expiry_interval)
          @clean = false
        end

        def disconnected!
          # We can start the timeout here rather than tracking all packet activity because there is no
          # method to recover an in memory session from a full crash.
          @expiry_timeout&.start!
        end

        def expired?
          @expiry_timeout&.expired?
        end

        def clean?
          @clean
        end

        def disconnect_expiry_interval
          0  # Memory sessions don't survive disconnect anyway
        end

        def store_packet(packet, replace: false)
          raise KeyError, 'packet id already exists' if !replace && stored_packet?(packet.id)

          @store[packet.id] = packet
        end

        def delete_packet(id)
          @store.delete(id)
        end

        def stored_packet?(id)
          @store.key?(id)
        end

        def retry_packets
          @store.values
        end

        def qos2_recover
          [] # nothing to recover
        end

        def qos_unhandled_packets
          {} # nothing was persisted
        end

        def store_qos_received(packet, unique_id)
          # For memory store, we don't need to persist received packets
          # This is just for tracking during the current session
        end

        def qos_handled(packet, unique_id)
          # For memory store, we don't need to persist handled status
          # This is just for tracking during the current session
        end

        def qos2_release(id)
          # For memory store, we don't need to persist QoS2 release status
          # This is just for tracking during the current session
        end

        def restart_clone
          self # don't actually clone.
        end
      end
    end
  end
end
