# frozen_string_literal: true

require 'mqtt/core/client'
require_relative '../packet'

module MQTT
  module V5
    class Client < MQTT::Core::Client
      # Client Session specialisation for MQTT 5.0
      class Session < MQTT::Core::Client::Session
        attr_reader :response_base

        # If client id was set non-empty, then this is just used
        # If not set, or explicitly empty or explicitly nil, then use server-assigned client id
        def connect_data(**connect)
          check_session_managed_fields(:connect, connect, :clean_start, :session_expiry_interval)
          super.merge!(
            {
              clean_start: clean?,
              session_expiry_interval: session_store.expiry_interval
            }
          )
        end

        # There seems to be no real use for updating the session_expiry_interval on disconnect,
        # and there are potential issues because we don't get an ack to know if the broker ever received it.
        def disconnect_data(**disconnect)
          check_session_managed_fields(:disconnect, disconnect, :session_expiry_interval)
          super
        end

        def connected!(connect, connack)
          session_store.client_id = connack.assigned_client_identifier if connack.assigned_client_identifier
          session_store.expiry_interval = connack.session_expiry_interval if connack.session_expiry_interval
          @response_base = connack.response_information if connack.response_information
          super
        end

        private

        def qos2_response(response_name, id, exists, **data)
          # Use reason code instead of raise protocol error
          super(response_name, id, true, reason_code: exists ? 0x00 : 0x92, **data)
        end
      end
    end
  end
end
