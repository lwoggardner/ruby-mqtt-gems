# frozen_string_literal: true

require_relative 'socket_factory'
require_relative 'qos_tracker'
require_relative '../../logger'
require 'forwardable'
require 'concurrent_monitor'

module MQTT
  module Core
    class Client
      # @!visibility private
      # Common session handling across MQTT protocol versions
      #   * responsible for building packets from user data for PUBLISH, SUBSCRIBE, UNSUBSCRIBE
      #   * handles the protocol for a given client id - packet identifier assignment, QOS handling
      #   * spans connections - retries by resending packets from the unacknowledged packet store
      # @abstract - MQTT Protocol version specific session behaviour in concrete implementations
      class Session
        extend Forwardable
        include Logger
        include ConcurrentMonitor
        include QosTracker

        def initialize(client:, monitor:, session_store:)
          @client = client
          @monitor = monitor.new_monitor
          @session_store = session_store

          qos_initialize
        end

        def connect_data(**connect)
          check_session_managed_fields(:connect, connect, :client_id)
          { client_id: session_store.client_id }
        end

        def disconnect_data(**_disconnect)
          {}
        end

        def expired!(clean: clean?)
          return if clean || !session_store.expired?

          raise SessionExpired, "Session #{session_store} for '#{client_id}' has expired"
        end

        def connected!(_connect, connack)
          return session_store.connected! if connack.session_present? || clean?

          expired!(clean: false)
          raise SessionNotPresent, "Server does not have a session for '#{client_id}'"
        end

        # Sending a message, store a duplicate packet in the packet store for resending
        def publish(qos: 0, **publish)
          check_session_managed_fields(__method__, publish, :packet_identifier, :dup)
          validate_qos!(qos)

          dup = packet_with_id(:publish, qos:, dup: true, **publish) if qos.positive?

          p = build_packet(:publish, qos:, dup: false, packet_identifier: dup&.id, **publish)
          yield p
        end

        def subscribe(**subscribe)
          check_session_managed_fields(__method__, subscribe, :packet_identifier)
          pkt = packet_with_id(:subscribe, **subscribe)
          validate_qos!(pkt.max_qos)

          yield pkt
        end

        def unsubscribe(**unsubscribe)
          check_session_managed_fields(__method__, unsubscribe, :packet_identifier)
          yield packet_with_id(:unsubscribe, **unsubscribe)
        end

        # Receiving a message
        def handle_publish(packet)
          # Notify the client the message has been received (unless we are qos and have already seen it)
          unless packet.qos == 2 && qos2_published?(packet.id)
            matched_subs = receive_publish(packet)
            qos_received(packet, matched_subs.size) if packet.qos.positive?
            matched_subs.each { |sub| sub.put(packet) }
          end

          return unless packet.qos.positive?

          # Build and send the appropriate ACK packet
          ack = build_packet(packet.qos == 2 ? :pubrec : :puback, packet_identifier: packet.id)
          push_packet(ack)
        end

        # replace the stored publish message with a pubrel message
        def handle_pubrec(packet)
          packet.success!
          # We don't need to sync this as the only possible conflict would be a protocol error
          # anyway, so we will always see pub_rec after publish.
          pubrel = store_packet(qos2_response(:pubrel, packet.id, stored_packet?(packet.id)), replace: true)
          push_packet(pubrel)
        rescue ResponseError => _e
          release_packet(packet)
        end

        def handle_pubrel(packet)
          push_packet(qos2_response(:pubcomp, packet.id, qos2_release(packet.id)))
        end

        def release_packet(packet)
          # Notify the client the request has been acknowledged
          receive_ack(packet)
        ensure
          delete_packet(packet.id)
        end

        alias handle_puback release_packet
        alias handle_pubcomp release_packet
        alias handle_suback release_packet
        alias handle_unsuback release_packet
        private :release_packet

        MAX_PACKET_ID = 65_535

        def max_packet_id
          MAX_PACKET_ID
        end

        def_delegators :session_store, :disconnected!, :client_id, :retry_packets, :expiry_interval=,
                       :max_qos, :validate_qos!

        private

        attr_reader :session_store

        # Client helpers and callbacks
        def_delegators :@client, :build_packet, :deserialize, :push_packet, :receive_ack, :receive_publish

        # Session store interface
        def_delegators :session_store, :clean?, :expired?, :stored_packet?, :store_packet, :delete_packet

        # used in handle PUBREC/PUBREL to handle unknown packet id errors
        def qos2_response(response_name, id, exists, **data)
          raise ProtocolError, "Packet id #{id} does not exist in session for #{client_id}" unless exists

          build_packet(response_name, packet_identifier: id, **data)
        end

        def packet_with_id(packet_type, **packet_data)
          next_packet_id { |id| build_packet(packet_type, packet_identifier: id, **packet_data) }
        end

        # Generates unique packet IDs for a single client session.
        # Uses random allocation and initial optimistic collision check before any synchronisation around use
        # of the session store.
        # The cost of generating a random number is low compared to the RTT for QOS 1/2 flow.
        def next_packet_id(&)
          init_id = rand(1..max_packet_id)
          attempts = 0
          loop do
            result = claim_id(((init_id + attempts) % max_packet_id) + 1, &)

            return result if result

            packet_id_backoff(attempts += 1)
          end
        end

        def claim_id(id)
          return nil if stored_packet?(id)

          packet = yield id

          synchronize { packet.tap { store_packet(packet) } unless stored_packet?(packet.id) }
        end

        def packet_id_backoff(attempts)
          return unless attempts >= max_packet_id

          # if we've done a whole lap of available ids, start backing off...
          log.warn { "Packet id contention: #{attempts} attempts" } if (attempts % max_packet_id).zero?
          sleep(0.01 * Math.log(attempts - max_packet_id + 2))
        end

        def check_session_managed_fields(packet_type, data, *invalid_fields)
          data.delete_if do |k, _v|
            next false unless invalid_fields.include?(k)

            log.warn { "#{packet_type}: Ignoring session managed property #{k}" }
            true
          end
        end
      end
    end
  end
end
