# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module JsonRpcSpec
      def self.included(base)
        base.class_eval do
          describe 'JSON-RPC' do
            it 'basic JSON-RPC call' do
              skip 'JSON-RPC implementation - to be implemented'
              
              with_client do |responder_client|
                responder_client.connect
                responder_client.json_rpc_responder('test/api') do |method, params|
                  { method: method, params: params }
                end
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect
                  rpc = requester_client.json_rpc_requester('test/api')
                  result = rpc.call('test_method', foo: 'bar', timeout: 2)
                  
                  _(result[:method]).must_equal('test_method')
                  _(result[:params][:foo]).must_equal('bar')
                end
              end
            end

            it 'method_missing for natural Ruby calls' do
              skip 'JSON-RPC implementation - to be implemented'
              
              with_client do |responder_client|
                responder_client.connect
                responder_client.json_rpc_responder('test/api') do |method, params|
                  { success: true, called: method }
                end
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect
                  rpc = requester_client.json_rpc_requester('test/api')
                  result = rpc.restart(device_id: '123')
                  
                  _(result[:success]).must_equal(true)
                  _(result[:called]).must_equal('restart')
                end
              end
            end

            it 'JSON-RPC error handling' do
              skip 'JSON-RPC implementation - to be implemented'
              
              with_client do |responder_client|
                responder_client.connect
                responder_client.json_rpc_responder('test/api') do |method, params|
                  raise 'Something went wrong'
                end
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect
                  rpc = requester_client.json_rpc_requester('test/api')
                  
                  err = _(proc { rpc.call('failing_method', timeout: 2) }).must_raise(JsonRpcError)
                  _(err.code).must_equal(-32603)
                  _(err.message).must_equal('Something went wrong')
                end
              end
            end

            it 'object dispatch' do
              skip 'JSON-RPC implementation - to be implemented'
              
              with_client do |responder_client|
                responder_client.connect
                
                service = Object.new
                def service.restart(device_id:)
                  { restarted: device_id }
                end
                
                responder_client.json_rpc_responder('test/api', service)
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect
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
end

MQTT::V5::SpecHelper.client_spec(MQTT::V5::JsonRpcSpec)
