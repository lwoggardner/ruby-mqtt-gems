# frozen_string_literal: true

require 'mqtt/core/client'
require_relative 'packets'
require_relative 'client/connection'
require_relative 'client/session'

module MQTT
  module V3
    # An MQTT 3.1.1 Client
    class Client < MQTT::Core::Client
      class << self
        def packet_module
          Packet
        end

        def protocol_version
          3
        end
      end
    end
  end
end
