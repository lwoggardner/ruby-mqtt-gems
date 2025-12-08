# frozen_string_literal: true

require 'securerandom'

module MQTT
  module V5
    class Client
      # Requester handles making requests and receiving responses
      # Setup once (typically in on_birth) and reuse for multiple requests
      class Requester
        def initialize(client, request_topic)
          @client = client
          @request_topic = request_topic
          @pending = {}
          
          # Subscribe immediately to response topic
          base = "#{@client.session.response_base}/#{@request_topic}/#"
          @subscription = @client.subscribe(base).async do |topic, payload, correlation_data:, **attrs|
            @pending[correlation_data]&.complete(payload)
          end
        end
        
        # Make a request and wait for response
        # @param payload [String] the request payload
        # @param timeout [Numeric] timeout in seconds
        # @param qos [Integer] QoS level (0, 1, or 2)
        # @return [String] the response payload
        def request(payload:, timeout: 5, qos: 1)
          correlation_data = SecureRandom.uuid
          response_topic = "#{@client.session.response_base}/#{@request_topic}/#{correlation_data}"
          
          future = ConcurrentMonitor::Future.new
          @pending[correlation_data] = future
          
          @client.publish(@request_topic, payload,
            qos: qos,
            response_topic: response_topic,
            correlation_data: correlation_data
          )
          
          future.value(timeout: timeout)
        ensure
          @pending.delete(correlation_data)
        end
      end
      
      # Create a Requester for the given topic
      # @param topic [String] the request topic
      # @return [Requester]
      def requester(topic)
        Requester.new(self, topic)
      end
      
      # Setup a responder for the given topic
      # @param topic [String] the request topic to subscribe to
      # @param qos [Integer] QoS level for subscription
      # @yield [payload] block that processes request and returns response
      # @return [Subscription] the subscription handling requests
      def responder(topic, qos: 1, &block)
        subscribe(topic, max_qos: qos).async do |req_topic, payload, response_topic:, correlation_data:, **attrs|
          response_payload = block.call(payload)
          
          publish(response_topic, response_payload,
            qos: qos,
            correlation_data: correlation_data
          )
        end
      end
    end
  end
end
