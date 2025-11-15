# frozen_string_literal: true

require 'mqtt/core/client'
require_relative '../packet'

module MQTT
  module V3
    class Client < MQTT::Core::Client
      # Client Session specialisation for MQTT 3.1.1
      #
      # Session expiry and auto-assigned client ids are simulated since they are not supported by the protocol itself.
      #  * An empty client_id and non-zero expiry_interval will auto-generate an id at the first connection.
      #  * Session expiry is only checked on the client side before sending a CONNECT packet.
      #  * The clean_session property is always set true for anonymous sessions (zero expiry + client_id empty) and
      #    this combination is not recoverable.
      class Session < MQTT::Core::Client::Session
        # If session expiry is non-zero and client_id is empty, then auto generate a client_id if supported by
        # the session_store.

        def connect_data(**connect)
          check_session_managed_fields(:connect, connect, :clean_session)
          assign_client_id if client_id.empty? && session_store.expiry_interval.positive?
          super.merge!(client_id:, clean_session: clean?)
        end

        private

        # Anonymous sessions in MQTT3.0 are abandoned at disconnect.
        # If we have a long-lived session (ie with non-zero expiry) then we need to fake server assigned id by
        # generating one now.
        def assign_client_id
          session_store.client_id = session_store.generate_client_id
        end
      end
    end
  end
end
