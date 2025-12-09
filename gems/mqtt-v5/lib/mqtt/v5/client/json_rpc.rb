# frozen_string_literal: true

require 'json'

module MQTT
  module V5
    class JsonRpcError < StandardError
      attr_reader :code, :data

      def initialize(message, code: -32603, data: nil)
        super(message)
        @code = code
        @data = data
      end
    end

    # JSON-RPC requester wraps request/response with JSON-RPC protocol
    class JsonRpcRequester
      def initialize(requester)
        @requester = requester
        @id = 0
      end

      def call(method, **params)
        @id += 1
        timeout = params.delete(:timeout) || 5
        
        request = {
          jsonrpc: '2.0',
          method: method,
          params: params,
          id: @id
        }

        response_json = @requester.request(payload: JSON.generate(request), timeout: timeout)
        response = JSON.parse(response_json, symbolize_names: true)

        if response[:error]
          raise JsonRpcError.new(
            response[:error][:message],
            code: response[:error][:code],
            data: response[:error][:data]
          )
        end

        response[:result]
      end

      def method_missing(method, **params)
        call(method.to_s, **params)
      end

      def respond_to_missing?(method, include_private = false)
        true
      end
    end

    # JSON-RPC responder wraps responder with JSON-RPC protocol
    class JsonRpcResponder
      def initialize(client, topic, handler)
        @client = client
        @topic = topic
        @handler = handler
      end

      def start
        @client.responder(@topic) do |payload|
          request = JSON.parse(payload, symbolize_names: true)
          
          begin
            result = if @handler.respond_to?(:call)
              @handler.call(request[:method], request[:params] || {})
            else
              method = request[:method].to_sym
              @handler.public_send(method, **(request[:params] || {}))
            end

            response = {
              jsonrpc: '2.0',
              result: result,
              id: request[:id]
            }
          rescue => e
            response = {
              jsonrpc: '2.0',
              error: {
                code: -32603,
                message: e.message
              },
              id: request[:id]
            }
          end

          JSON.generate(response)
        end
      end
    end

    class Client
      def json_rpc_requester(topic)
        req = requester(topic)
        JsonRpcRequester.new(req)
      end

      def json_rpc_responder(topic, handler = nil, &block)
        handler ||= block
        responder = JsonRpcResponder.new(self, topic, handler)
        responder.start
      end
    end
  end
end
