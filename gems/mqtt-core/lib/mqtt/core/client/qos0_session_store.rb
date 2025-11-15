# frozen_string_literal: true

require_relative 'session_store'

module MQTT
  module Core
    class Client
      # A minimal Session Store limited to handling QoS0 packets only
      # Always a clean session on restart
      class Qos0SessionStore < SessionStore
        # @!visibility private
        # Allow server-assigned client ids (and anonymous sessions in MQTT 3)
        attr_writer :client_id

        def initialize(client_id: '')
          super(expiry_interval: 0, client_id:)
          @store = nil
        end

        def max_qos
          0
        end

        def connected!
          @store = Set.new
        end

        def disconnected!
          @store&.clear
        end

        # Always use a clean session
        def clean?
          true
        end

        # We still need to track packet id for subscribe/unsubscribe
        def store_packet(packet, **)
          raise KeyError, 'packet id already exists' unless @store.add?(packet.id)
        end

        def delete_packet(id)
          @store.delete(id)
        end

        def stored_packet?(id)
          @store.include?(id)
        end

        def retry_packets
          []
        end
      end
    end
  end
end
