# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module RequestResponseSpec
      def self.included(base)
        base.class_eval do
          describe 'Request/Response' do
            it 'simple request response' do
              
              with_client do |responder_client|
                responder_client.connect(request_response_information: true)
                topic = "test/service/#{responder_client.client_id}"
                
                # Set up responder
                responder_client.response(topic) do |topic, payload|
                  "echo: #{payload}"
                end
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect(request_response_information: true)
                  
                  response = requester_client.request(topic, "hello", message_expiry_interval: 2)
                  _(response).must_equal("echo: hello")
                end
              end
            end

            it 'concurrent requests' do
              with_client do |responder_client|
                responder_client.connect(request_response_information: true)
                topic = "test/service/#{responder_client.client_id}"
                
                # Set up responder
                responder_client.response(topic) do |topic, payload|
                  "response: #{payload}"
                end
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect(request_response_information: true)
                  
                  tasks = 3.times.map do |i|
                    requester_client.async do
                      requester_client.request(topic, "request-#{i}", message_expiry_interval: 2)
                    end
                  end
                  
                  responses = tasks.map(&:value)
                  _(responses.size).must_equal(3)
                  _(responses).must_include('response: request-0')
                  _(responses).must_include('response: request-1')
                  _(responses).must_include('response: request-2')
                end
              end
            end

            it 'timeout on no response' do
              with_client do |client|
                client.connect(request_response_information: true)
                topic = "test/noservice/#{client.client_id}"
                
                _(proc { client.request(topic, 'hello', message_expiry_interval: 0.5) }).must_raise(MQTT::V5::Client::RequestResponse::TimeoutError)
              end
            end

            it 'context with custom response base' do
              with_client do |client|
                client.connect(request_response_information: true)
                
                # Create custom context - use client's max QoS to work with all session stores
                qos = [client.max_qos, 1].min
                ctx = client.new_request_context('api', pub_opts: { qos: qos })
                
                _(ctx.response_base).must_match(/\/api$/)
                _(ctx.pub_opts[:qos]).must_equal(qos)
              end
            end

            it 'future vs blocking request' do
              with_client do |responder_client|
                responder_client.connect(request_response_information: true)
                topic = "test/future/#{responder_client.client_id}"
                
                responder_client.response(topic) do |topic, payload|
                  "echo: #{payload}"
                end
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect(request_response_information: true)
                  ctx = requester_client.default_request_context
                  
                  # Test future (non-blocking)
                  future = ctx.request(topic, 'test message', future: true)
                  _(future).must_be_kind_of(ConcurrentMonitor::Future)
                  future.wait(timeout: 2)
                  result = future.value
                  _(result).must_equal('echo: test message')
                  
                  # Test blocking request
                  result = ctx.request(topic, 'test message', message_expiry_interval: 2)
                  _(result).must_equal('echo: test message')
                end
              end
            end

            it 'shared responders load balancing' do
              # Test request/response with shared responders for load balancing
              # Use unique group name to avoid interference from previous test runs
              group_name = "responders-#{SecureRandom.uuid}"
              # And unique service topic to avoid interference from parallel tests
              service_topic = "test/service/#{SecureRandom.uuid}"
              shared_service_topic = "$share/#{group_name}/#{service_topic}"
              
              with_client do |requester|
                requester.connect(request_response_information: true)
                
                # Set up 3 responder clients (non-block form)
                responder_responses = [[], [], []]
                responders = []
                
                3.times do |i|
                  responder = with_client(session_store: requester.class.memory_store)
                  responder.connect(request_response_information: true)
                  
                  responder.response(shared_service_topic) do |topic, payload|
                    response = "responder#{i}: #{payload}"
                    responder_responses[i] << response
                    response
                  end
                  
                  responders << responder
                end
                
                sleep 0.5
                
                # Send 9 requests to test load balancing across 3 responders
                request_responses = []
                9.times do |i|
                  response = requester.request(service_topic, "request-#{i}", message_expiry_interval: 2)
                  request_responses << response
                end
                
                sleep 0.5
                
                # Verify all requests got responses
                _(request_responses.size).must_equal(9)
                
                # Verify load balancing - all responders should handle some requests
                total_handled = responder_responses.sum(&:size)
                _(total_handled).must_equal(9)
                
                # Each responder should handle at least one request
                responder_responses.each_with_index do |responses, i|
                  _(responses.size).must_be :>, 0, "responder#{i} should handle at least one request"
                end
                
                # Verify responses match requests and identify correct responder
                request_responses.each do |response|
                  _(response).must_match(/^responder[012]: request-\d+$/)
                end
                
                # Clean up responders
                responders.each(&:disconnect)
              end
            end

            it 'no response sent when processing exceeds expiry interval' do
              with_client do |server_client|
                # Track publishes with correlation_data (responses)
                response_publishes = []
                server_client.on_publish do |publish, ack|
                  response_publishes << publish if publish.correlation_data
                end
                
                server_client.connect(request_response_information: true)
                
                expiry = (1 * timing_factor).ceil
                # Set up responder that takes longer than expiry
                server_client.response('test/slow') do |topic, payload|
                  sleep expiry * 3
                  'too late'
                end
                
                with_client(session_store: server_client.class.memory_store) do |client|
                  client.connect(request_response_information: true)
                  
                  begin
                    client.request('test/slow', 'data', message_expiry_interval: expiry)
                  rescue MQTT::Error
                    # Expected to timeout
                  end
                  
                  # Wait for processing to complete
                  sleep expiry * 4
                  
                  _(response_publishes).must_be_empty
                end
              end
            end
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::V5::RequestResponseSpec, protocol_version: 5)
