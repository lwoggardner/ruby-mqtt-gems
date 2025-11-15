# frozen_string_literal: true

require_relative '../packet'

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 PINGREQ packet
      #
      # Sent by client to keep the connection alive.
      #
      # @see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Toc398718081 MQTT 3.1.1 Spec §3.12
      class PingReq
        include Packet

        fixed(12)
      end
    end
  end
end
