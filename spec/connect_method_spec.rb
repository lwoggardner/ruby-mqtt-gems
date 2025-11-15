# frozen_string_literal: true
require_relative 'spec_helper'

module MQTT
  module ConnectMethodSpec
    def self.included(spec)
      spec.class_eval do
        it 'connects explicitly' do
          with_client do |client|
            _(client.status).must_equal(:configure)
            client.connect
            _(client.status).must_equal(:connected)
          end
        end

        it 'connects with configuration options' do
          with_client do |client|
            client.connect(keep_alive: 60)
            _(client.status).must_equal(:connected)
          end
        end

        it 'supports birth handler with explicit connect' do
          with_client do |client|
            birth_called = false
            client.on_birth { birth_called = true }
            client.connect
            wait_until(5) { birth_called }
            _(birth_called).must_equal(true)
            _(client.status).must_equal(:connected)
          end
        end

        describe 'connection failure' do
          let(:uri) { 'mqtt://localhost:9999' }
          
          it 'raises error on connection failure' do
            with_client do |client|
              _(proc { client.connect }).must_raise(MQTT::ConnectionError)
            end
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::ConnectMethodSpec)