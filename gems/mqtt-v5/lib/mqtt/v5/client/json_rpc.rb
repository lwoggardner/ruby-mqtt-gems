# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'mqtt/v5/client/request_response'

module MQTT
  module V5
    class Client
      # JSON-RPC 2.0 Requester
      class JsonRpcRequester
        def initialize(requester)
          @requester = requester
        end
        
        # Make a JSON-RPC call
        # @param method [String] the method name
        # @param params [Hash] the method parameters
        # @param timeout [Numeric] timeout in seconds
        # @return [Object] the result from the JSON-RPC response
        # @raise [JsonRpcError] if the response contains an error
        def call(method, params = {}, timeout: 5)
          request = {
            jsonrpc: '2.0',
            method: method,
            params: params,
            id: SecureRandom.uuid
          }
          
          response_json = @requester.request(
            payload: JSON.generate(request),
            timeout: timeout
          )
          
          response = JSON.parse(response_json, symbolize_names: true)
          raise JsonRpcError.new(response[:error]) if response[:error]
          response[:result]
        end
        
        # Allow natural Ruby method calls via method_missing
        def method_missing(method, **kwargs)
          call(method.to_s, kwargs)
        end
        
        def respond_to_missing?(method, include_private = false)
          true
        end
      end
      
      # JSON-RPC 2.0 Error
      class JsonRpcError < StandardError
        attr_reader :code, :data
        
        def initialize(error)
          @code = error[:code]
          @data = error[:data]
          super(error[:message])
        end
      end
      
      # Create a JSON-RPC requester for the given topic
      # @param topic [String] the request topic
      # @return [JsonRpcRequester]
      def json_rpc_requester(topic)
        JsonRpcRequester.new(requester(topic))
      end
      
      # Setup a JSON-RPC responder for the given topic
      # @param topic [String] the request topic to subscribe to
      # @param handler [Object] optional object to dispatch methods to
      # @param qos [Integer] QoS level for subscription
      # @yield [method, params] block that handles the method call
      # @return [Subscription] the subscription handling requests
      def json_rpc_responder(topic, handler = nil, qos: 1, &block)
        responder(topic, qos: qos) do |payload|
          req = JSON.parse(payload, symbolize_names: true)
          
          begin
            # Dispatch to object or block
            result = if handler
              handler.public_send(req[:method], **req[:params].transform_keys(&:to_sym))
            else
              block.call(req[:method], req[:params] || {})
            end
            
            response = { jsonrpc: '2.0', result: result, id: req[:id] }
          rescue => e
            response = {
              jsonrpc: '2.0',
              error: { code: -32603, message: e.message },
              id: req[:id]
            }
          end
          
          JSON.generate(response)
        end
      end
    end
  end
end
