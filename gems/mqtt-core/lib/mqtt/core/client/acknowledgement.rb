# frozen_string_literal: true

require_relative '../../errors'

module MQTT
  module Core
    class Client
      # In MQTT the acknowledgement is always a packet
      class Acknowledgement < ConcurrentMonitor::Future
        def initialize(packet, monitor:, &deferred)
          @packet = packet
          @deferred = deferred
          super(monitor:)
        end

        #  @return [MQTT::Packet] the packet that this acknowledgement is for
        attr_reader :packet

        def cancel(exception)
          reject(exception)
        end

        def fulfill(ack_packet)
          super(@deferred ? @deferred.call(ack_packet) : [packet, ack_packet])
        rescue StandardError => e
          reject(e)
        end
      end
    end
  end
end
