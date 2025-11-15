# frozen_string_literal: true

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 DISCONNECT packet
      #
      # Sent by client to gracefully disconnect from the broker.
      #
      # @see Core::Client#disconnect
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718090 MQTT 3.1.1 Spec §3.14
      class Disconnect
        include Packet

        fixed(14)
      end
    end
  end
end
