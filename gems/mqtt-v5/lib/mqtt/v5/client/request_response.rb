# frozen_string_literal: true

require 'securerandom'

module MQTT
  module V5
    class Client
      # Requester handles making requests and receiving responses
      # Setup once (typically in on_birth) and reuse for multiple requests
      class Requester
        def initialize(client, request_topic, response_base)
          @client = client
          @request_topic = request_topic
          @response_base = response_base
          @pending = {}
          
          # Subscribe immediately to response topic and start async handler
          base = "#{@response_base}/#{@request_topic}/#"
          sub = @client.subscribe(base)
          @task = sub.async_packets do |packet|
            correlation_data = packet.correlation_data
            @pending[correlation_data]&.fulfill(packet.payload) if correlation_data
          end
        end
        
        # Make a request and wait for response
        # @param payload [String] the request payload
        # @param timeout [Numeric] timeout in seconds
        # @param qos [Integer] QoS level (0, 1, or 2)
        # @return [String] the response payload
        def request(payload:, timeout: 5, qos: 0)
          correlation_data = SecureRandom.uuid
          response_topic = "#{@response_base}/#{@request_topic}/#{correlation_data}"
          
          future = @client.new_future
          @pending[correlation_data] = future
          
          @client.publish(@request_topic, payload,
            qos: qos,
            response_topic: response_topic,
            correlation_data: correlation_data
          )
          
          future.wait(timeout, exception: ::RuntimeError)
          future.value
        ensure
          @pending.delete(correlation_data)
        end
      end
      
      # Create a Requester for the given topic
      # @param topic [String] the request topic
      # @return [Requester]
      def requester(topic)
        response_base = session.response_base || "response"
        Requester.new(self, topic, response_base)
      end
      
      # Setup a responder for the given topic
      # @param topic [String] the request topic to subscribe to
      # @param qos [Integer] QoS level for subscription
      # @yield [payload] block that processes request and returns response
      # @return [Subscription] the subscription handling requests
      def responder(topic, qos: 0, &block)
        sub = subscribe(topic, max_qos: qos)
        task = sub.async_packets do |packet|
          next unless packet.response_topic
          
          response_payload = block.call(packet.payload)
          
          publish(packet.response_topic, response_payload,
            qos: qos,
            correlation_data: packet.correlation_data
          )
        end
        [sub, task]
      end
    end
  end
end
