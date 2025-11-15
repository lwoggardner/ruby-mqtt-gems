# frozen_string_literal: true

module MQTT
  module V3
    module Packet
      # MQTT 3.1.1 acknowledgement module
      #
      # Most V3 ACK packets have no error codes - the packet arrives successfully, or the connection is closed.
      # This module provides success!, success?, and failed? methods for these packets.
      module AckSuccess
        def success?
          true
        end

        def success!
          self
        end

        def failed?
          false
        end
      end
    end
  end
end
