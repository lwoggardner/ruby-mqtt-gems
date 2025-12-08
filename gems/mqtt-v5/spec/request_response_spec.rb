# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module RequestResponseSpec
      def self.included(base)
        base.class_eval do
          describe 'Request/Response' do
            it 'basic request/response' do
              with_client_pair do |requester_client, responder_client|
                responder_client.responder('test/service') do |payload|
                  "echo: #{payload}"
                end
                
                req = requester_client.requester('test/service')
                response = req.request(payload: 'hello', timeout: 2)
                
                _(response).must_equal('echo: hello')
              end
            end

            it 'concurrent requests' do
              with_client_pair do |requester_client, responder_client|
                responder_client.responder('test/service') do |payload|
                  "response: #{payload}"
                end
                
                req = requester_client.requester('test/service')
                
                tasks = 3.times.map do |i|
                  requester_client.async do
                    req.request(payload: "request-#{i}", timeout: 2)
                  end
                end
                
                responses = tasks.map(&:join)
                _(responses.size).must_equal(3)
                _(responses).must_include('response: request-0')
                _(responses).must_include('response: request-1')
                _(responses).must_include('response: request-2')
              end
            end

            it 'timeout on no response' do
              with_client do |client|
                req = client.requester('test/noservice')
                
                _(proc { req.request(payload: 'hello', timeout: 0.5) }).must_raise(ConcurrentMonitor::WaitTimeout)
              end
            end
          end
        end
      end
    end
  end
end

MQTT::V5::SpecHelper.client_spec(MQTT::V5::RequestResponseSpec)
