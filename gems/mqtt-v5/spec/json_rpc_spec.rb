# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module JsonRpcSpec
      def self.included(base)
        base.class_eval do
          describe 'JSON-RPC' do
            it 'basic JSON-RPC call' do
              with_client_pair do |requester_client, responder_client|
                responder_client.json_rpc_responder('test/api') do |method, params|
                  { method: method, params: params }
                end
                
                rpc = requester_client.json_rpc_requester('test/api')
                result = rpc.call('test_method', foo: 'bar', timeout: 2)
                
                _(result[:method]).must_equal('test_method')
                _(result[:params][:foo]).must_equal('bar')
              end
            end

            it 'method_missing for natural Ruby calls' do
              with_client_pair do |requester_client, responder_client|
                responder_client.json_rpc_responder('test/api') do |method, params|
                  { success: true, called: method }
                end
                
                rpc = requester_client.json_rpc_requester('test/api')
                result = rpc.restart(device_id: '123')
                
                _(result[:success]).must_equal(true)
                _(result[:called]).must_equal('restart')
              end
            end

            it 'JSON-RPC error handling' do
              with_client_pair do |requester_client, responder_client|
                responder_client.json_rpc_responder('test/api') do |method, params|
                  raise 'Something went wrong'
                end
                
                rpc = requester_client.json_rpc_requester('test/api')
                
                err = _(proc { rpc.call('failing_method', timeout: 2) }).must_raise(JsonRpcError)
                _(err.code).must_equal(-32603)
                _(err.message).must_equal('Something went wrong')
              end
            end

            it 'object dispatch' do
              with_client_pair do |requester_client, responder_client|
                service = Object.new
                def service.restart(device_id:)
                  { restarted: device_id }
                end
                
                responder_client.json_rpc_responder('test/api', service)
                
                rpc = requester_client.json_rpc_requester('test/api')
                result = rpc.restart(device_id: 'device-1')
                
                _(result[:restarted]).must_equal('device-1')
              end
            end
          end
        end
      end
    end
  end
end

MQTT::V5::SpecHelper.client_spec(MQTT::V5::JsonRpcSpec)
