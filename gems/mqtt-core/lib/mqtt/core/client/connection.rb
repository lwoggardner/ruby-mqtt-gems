# frozen_string_literal: true

require 'forwardable'
require 'concurrent_monitor'
require_relative '../../logger'

module MQTT
  module Core
    class Client
      # @!visibility private
      # Represents a single network connection to an MQTT Server
      class Connection
        extend Forwardable
        include Logger
        include ConcurrentMonitor

        def initialize(client:, session:, io:, monitor:)
          @client = client
          @monitor = monitor.new_monitor
          @session = session
          @io = io
        end

        # Connect runs synchronously reading packets and getting responses
        # until the connection handshakes are complete.
        def connect(**connect_data)
          [send_packet(connect_packet(**connect_data)), complete_connection(receive_packet)]
        end

        # Build and send a disconnect packet
        def disconnect(exception = nil, **disconnect)
          if exception
            io.close
          else
            yield disconnect_packet(**disconnect)
          end
        end

        # @yield(packet, action:)
        # @yieldparam [Packet] packet the packet to handle
        # @yieldparam [Symbol] action the action to take,
        #   :send to forward a packet as part of protocol flow
        #   :acknowledge the packet is a response to a client request
        #   :handle other types of packets
        # @yieldreturn [void]
        def receive_loop
          loop { return unless handle_packet(receive_packet) }
        ensure
          io.close_read if io.respond_to?(:close_read) && !io.closed?
        end

        def send_loop
          packet = pingreq_packet
          loop do
            packet = (yield ping_remaining(packet)) || pingreq_packet
            return unless send_packet(packet)
          end
        ensure
          io.close_write if io.respond_to?(:close_write) && !io.closed?
        end

        # Session handles publish, subscribe, and unsubscribe, but versioned subclasses may override
        def_delegators :session, :publish, :subscribe, :unsubscribe

        def connected?
          !io.closed?
        end

        def close
          io.close
        end

        attr_reader :keep_alive, :ping_clock

        private

        attr_reader :io, :session, :client

        def_delegators :session, :max_packet_id, :generate_client_id, :retry_packets
        def_delegators :client, :build_packet, :push_packet, :deserialize

        def ping_remaining(prev_packet)
          return 0 unless ping_clock

          # if client is only sending QOS 0 publish, we need to send a ping to
          # prevent the recv loop timing out, and thus proving we have bidirectional connectivity
          prev_packet = pingreq_packet.tap { |ping| send_packet(ping) } if ping_clock.expired?
          ping_clock.start! unless prev_packet.packet_name == :publish && prev_packet.qos.zero?

          ping_clock.remaining
        end

        def send_packet(packet)
          log.debug { "SEND: #{packet}" }
          client.handle_event(:send, packet == :eof ? nil : packet)
          return false if packet == :eof

          packet.serialize(io)

          # cause loop to stop after disconnect is sent
          return false if packet.packet_name == :disconnect

          packet
        end

        def receive_packet
          deserialize(io)
            .tap { |p| log.debug { "RECV: #{p || :eof}" } }
            .tap { |p| client.handle_event(:receive, p) }
        end

        # Allow version-specific subclass to handle additional connection flow (eg auth in 5.0)
        def complete_connection(received_packet)
          raise EOFError unless received_packet

          received_packet.tap do |connack|
            handle_connack(connack)
          end
        end

        def connect_packet(**connect)
          build_packet(:connect, **connect_data(**connect)).tap do |p|
            self.keep_alive = p.keep_alive
          end
        end

        def keep_alive=(val)
          @keep_alive = val
          @ping_clock = (val&.positive? ? ConcurrentMonitor::TimeoutClock.timeout(val) : nil)
          io.timeout = (val&.positive? ? val * 2.0 : nil)
        end

        def connect_data(**connect)
          connect.merge!(session.connect_data(**connect))
        end

        def pingreq_packet
          @pingreq_packet ||= build_packet(:pingreq)
        end

        def disconnect_packet(**disconnect)
          build_packet(:disconnect, **disconnect_data(**disconnect))
        end

        def disconnect_data(**disconnect)
          disconnect.merge!(session.disconnect_data(**disconnect))
        end

        def handle_packet(packet)
          # an empty packet means end of stream in the read loop, we'll try and gracefully inform the send loop
          return handle_eof if !packet && !io.closed? && io.eof?
          return nil unless packet

          send("handle_#{packet.packet_name}", packet)
          true
        end

        def handle_connack(packet)
          raise ProtocolError, 'Unexpected packet type' unless packet.packet_name == :connack

          packet.success!
        end

        def handle_pingresp(_packet)
          # nothing to handle
        end

        # QOS 1/2 flow - when this client has sent a message via PUBLISH
        def_delegators :session, :handle_puback, :handle_pubrec, :handle_pubcomp

        # QOS 1/2 flow - when this client has received a message
        def_delegators :session, :handle_publish, :handle_pubrel

        # Other acks
        def_delegators :session, :handle_suback, :handle_unsuback

        # This is if the server explicitly sends a disconnect,  which would always expect to be an error
        def handle_disconnect(packet)
          packet.success!
        ensure
          io.close
        end

        def handle_eof
          client.receive_eof
          false
        end
      end
    end
  end
end
