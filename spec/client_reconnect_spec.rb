# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module ClientReconnectSpec
    def self.included(spec)
      spec.class_eval do
        describe 'reconnections' do
          it 'reconnects after network error' do
            reconnect_count = 0
            MQTT.open(uri, **client_class_opts, keep_alive: 1.0) do |client|
              client.on_disconnect do |_count, &raiser|
                raiser.call
              rescue StandardError
                reconnect_count += 1
              end

              client.on_receive do |packet|
                raise EOFError, 'fake eof' if packet&.packet_name == :pingresp
              end

              client.connect
              sleep 4.0
              _(reconnect_count).must_be :>=, 1
            end
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::ClientReconnectSpec)
