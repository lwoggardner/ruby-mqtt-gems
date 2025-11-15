# frozen_string_literal: true

module MQTT
  module QoSReliability
    # Witness Client - Verify packets sent or received
    class PacketWitness
      attr_reader :tracked_packets

      def initialize
        @tracked_packets = Hash.new { |h, k| h[k] = [] }
      end

      def send(packet)
        @tracked_packets[:send] << packet
      end

      def receive(packet)
        @tracked_packets[:receive] << packet
      end

      def sent(packet_type, **packet_attributes)
        matches(:send, packet_type, **packet_attributes)
      end

      def received(packet_type, **packet_attributes)
        matches(:receive, packet_type, **packet_attributes)
      end

      private

      def matches(direction, packet_name, **packet_attributes)
        tracked_packets[direction].select do |packet|
          packet.packet_name == packet_name && packet_attributes.all? { | k,v | packet.send(k) == v}
        end
      end
    end
  end
end