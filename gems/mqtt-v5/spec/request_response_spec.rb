# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module RequestResponseSpec
      def self.included(base)
        base.class_eval do
          describe 'Request/Response' do
            it 'concurrent requests' do
              with_client do |responder_client|
                responder_client.connect
                responder_client.responder('test/service') do |payload|
                  "response: #{payload}"
                end
                
                with_client(session_store: responder_client.class.memory_store) do |requester_client|
                  requester_client.connect
                  req = requester_client.requester('test/service')
                  
                  tasks = 3.times.map do |i|
                    requester_client.async do
                      req.request(payload: "request-#{i}", timeout: 2)
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
                client.connect
                req = client.requester('test/noservice')
                
                _(proc { req.request(payload: 'hello', timeout: 0.5) }).must_raise(RuntimeError)
              end
            end
          end
        end
      end
    end
  end
end

MQTT::V5::SpecHelper.client_spec(MQTT::V5::RequestResponseSpec)
