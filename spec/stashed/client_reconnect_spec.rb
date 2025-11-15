# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module ClientReconnectSpec
    def self.included(spec)
      spec.class_eval do

        describe 'reconnections' do

          def with_client(&block)
            MQTT.open(uri, **client_class_opts, connect_timeout:) do |client|
              block.call(client)
            end
          end

          it 'stays connected' do
            retry_count = 0
            client_class_opts[:keep_alive] = 1.0
            with_client do |client|
              client.on_disconnect do |_count, &raiser|
                raiser.call
              rescue IOError
                retry_count += 1
                sleep(0.1)
              end

              client.on_receive do |packet|
                raise EOFError, 'fake eof' if packet&.packet_name == :pingresp
              end

              client.on_connect do |connect, connack|
                retry_count += 1
              end

              _(client.status).must_equal :configure
              warn 'before sleep'
              sleep 4.0
              warn 'after sleep'
              _(retry_count).must_be :>=, 1
              warn 'checked retry count'
            end
          end

          it 'maintains the previous server generated client_id'
          it 'retries if the connection fails'
          it 'retries if SSL/TLS connection fails'
          it 'abandons after retry limit is reached'
          it 'resends unfinished qos 1 and 2 messages'
          it 'stays subscribed to topics'
          it 'resets the retry count on reconnect'

          it 'does not reconnect if session has expired'

        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::ClientReconnectSpec)

