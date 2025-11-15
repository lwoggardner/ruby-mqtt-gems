# frozen_string_literal: true

require 'mqtt/core/client'
module MQTT
  module V3
    class Client < MQTT::Core::Client
      # Client protocol for MQTT 5.0
      class Connection < MQTT::Core::Client::Connection
        def_delegators :session, :clean_session

        def handle_publish(packet)
          raise ProtocolError, 'Received PUBLISH with DUP and QoS 0' if packet.qos.zero? && packet.dup

          super
        end
      end
    end
  end
end
