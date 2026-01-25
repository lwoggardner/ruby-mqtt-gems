# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module JsonRpcSpec
      def self.included(base)
        base.class_eval do
          describe 'JSON-RPC' do
            it 'basic request/response' do
              with_client do |server_client|
                server_client.connect(request_response_information: true)
                topic = "rpc/calculator"
                
                # Set up JSON-RPC responder
                server_client.json_rpc_service(topic) do |request_opts, response_opts, id, method, *args, **kwargs|
                  case method
                  when 'add' then args.sum
                  when 'multiply' then args.reduce(:*)
                  when 'greet' then "Hello, #{kwargs[:name]}!"
                  else raise NoMethodError, "Unknown method: #{method}"
                  end
                end
                
                with_client(session_store: server_client.class.memory_store) do |client_client|
                  client_client.connect(request_response_information: true)
                  
                  # Create JSON-RPC endpoint
                  calc = client_client.json_rpc_endpoint(topic)
                  
                  # Test positional arguments
                  result = calc.with(timeout: 2).add(5, 10)
                  _(result).must_equal(15)
                  
                  # Test named arguments  
                  result = calc.with(timeout: 2).greet(name: 'World')
                  _(result).must_equal('Hello, World!')
                  
                  # Test method not found
                  _(proc { calc.with(timeout: 1).unknown_method }).must_raise(NoMethodError)
                end
              end
            end

            it 'notifications (no response)' do
              with_client do |server_client|
                server_client.connect(request_response_information: true)
                topic = "rpc/logger/#{rand(10000)}"  # Unique topic per test
                
                received_logs = []
                server_client.json_rpc_service(topic) do |request_opts, response_opts, id, method, *args, **kwargs|
                  received_logs << { method: method, args: args, kwargs: kwargs }
                  nil # No response for notifications
                end
                
                with_client(session_store: server_client.class.memory_store) do |client_client|
                  client_client.connect(request_response_information: true)
                  
                  logger = client_client.json_rpc_endpoint(topic)
                  
                  # Send notification (no response expected)
                  logger.log!(message: 'test message', level: 'info')
                  
                  # Give it time to process
                  sleep 0.1
                  
                  _(received_logs.size).must_equal(1)
                  _(received_logs.first[:method]).must_equal('log')
                  _(received_logs.first[:args]).must_equal([])
                  _(received_logs.first[:kwargs]).must_equal({ message: 'test message', level: 'info' })
                end
              end
            end

            it 'futures (non-blocking)' do
              with_client do |server_client|
                server_client.connect(request_response_information: true)
                topic = "rpc/slow_service"
                
                server_client.json_rpc_service(topic) do |request_opts, response_opts, id, method, *args, **kwargs|
                  case method
                  when 'slowAdd'
                    sleep 0.1  # Simulate slow operation
                    args.sum
                  end
                end
                
                with_client(session_store: server_client.class.memory_store) do |client_client|
                  client_client.connect(request_response_information: true)
                  
                  service = client_client.json_rpc_endpoint(topic)
                  
                  # Start multiple requests concurrently
                  futures = 3.times.map do |i|
                    service.json_rpc_async(:next_id, :slowAdd, i, i + 1)
                  end
                  
                  # Collect results
                  results = futures.map do |f|
                    f.wait(timeout: 2)
                    f.value
                  end
                  
                  _(results).must_equal([1, 3, 5])  # 0+1, 1+2, 2+3
                end
              end
            end

            it 'custom context with different QoS' do
              with_client do |server_client|
                server_client.connect(request_response_information: true)
                topic = "rpc/critical_service"
                
                # Use the minimum of client max QoS and 2
                qos = [server_client.max_qos, 2].min
                
                server_client.json_rpc_service(topic, pub_opts: { qos: qos }) do |request_opts, response_opts, id, method, *args, **kwargs|
                  case method
                  when 'criticalOperation' then "success: #{kwargs.values.join(',')}"
                  end
                end
                
                with_client(session_store: server_client.class.memory_store) do |client_client|
                  client_client.connect(request_response_information: true)
                  
                  # Create context with appropriate QoS
                  ctx = client_client.new_request_context('critical', pub_opts: { qos: qos })
                  service = ctx.json_rpc_endpoint(topic, mqtt_qos: qos)
                  
                  result = service.with(timeout: 10).critical_operation(data1: 'test', data2: 'data')
                  _(result).must_equal('success: test,data')
                end
              end
            end

            it 'error handling' do
              with_client do |server_client|
                server_client.connect(request_response_information: true)
                topic = "rpc/error_service"
                
                server_client.json_rpc_service(topic) do |request_opts, response_opts, id, method, *args, **kwargs|
                  case method
                  when 'divide'
                    raise ArgumentError, "Division by zero" if args[1] == 0
                    args[0] / args[1]
                  when 'customError'
                    raise JsonRpcKit::Error.new("Custom error", code: -1000, extra: 'info')
                  end
                end
                
                with_client(session_store: server_client.class.memory_store) do |client_client|
                  client_client.connect(request_response_information: true)
                  
                  service = client_client.json_rpc_endpoint(topic)
                  
                  # Test ArgumentError mapping
                  _(proc { service.with(timeout: 1).divide(10, 0) }).must_raise(ArgumentError)
                  
                  # Test custom JSON-RPC error
                  error = _(proc { service.with(timeout: 1).custom_error }).must_raise(JsonRpcKit::Error)
                  _(error.code).must_equal(-1000)
                  _(error.data).must_equal({ extra: 'info' })
                end
              end
            end
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::V5::JsonRpcSpec, protocol_version: 5)
