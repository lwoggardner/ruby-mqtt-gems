# frozen_string_literal: true

require 'json_rpc_kit'
require_relative 'request_response'

module MQTT
  module V5
    class Client < MQTT::Core::Client
      # JSON-RPC over MQTT v5 Request/Response
      module JsonRpc
        # Create JSON-RPC Client endpoint over MQTT Request Response
        # @param topic [String]
        # @param request_context [RequestResponse::Context]
        # @param namespace [String] optional namespace prefix used to convert ruby method names to JSON-RPC convention
        # @param defaults [Hash] default publish options for JSON-RPC requests (eg qos:, user_properties:)
        # @return [JsonRpcKit::Endpoint] a client for invoking JSON-RPC methods
        def json_rpc_endpoint(topic, request_context: default_request_context, namespace: nil, **defaults)
          JsonRpcKit.endpoint(namespace:) do |id, request_json, async: false, timeout: nil, **pub_opts, &response|
            request_opts = { **defaults, **pub_opts, content_type: 'application/json' }
            next request_context.notify(topic, request_json, **request_opts) unless id

            future = request_context.future(
              topic, request_json, **request_opts, correlation_data: id
            ) do |payload, content_type: 'application/json', user_properties: {}, **|
              response.call(payload, content_type:, mqtt_properties: user_properties)
            end
            next future if async

            future.value(timeout, exception: JsonRpcKit::TimeoutError)
          end
        end

        # JSON-RPC Server via MQTT Request/Response subscription. Listening for requests, serving responses.
        # @overload json_rpc_service(receiver, *topics, **response_opts)
        #  @param receiver [JsonRpc::Service, :json_rpc_handle] the object to receive the JSON-RPC request
        #  @param topics [Array<String>] topic filters to listen for requests on
        #  @param response_opts [Hash] options for {RequestResponse#response}
        # @overload json_rpc_service(*topics, **response_opts, &receiver)
        #  @param topics [Array<String>] topic filters to listen for requests on
        #  @param response_opts [Hash] options for {RequestResponse#response}
        #  @yield [method, *args, rpc_topic:, rpc_user_properties, **kwargs] block to process the request
        #  @yieldparam method [String] the JSON_RPC method
        #  @yieldparam *args [Array] the JSON_RPC positional arguments
        #  @yieldparam rpc_mqtt_topic [String] the topic that the request was received on
        #  @yieldparam rpc_mqtt_properties [Hash<String,Array<String>>]
        #     user properties from the received MQTT message. This hash is mutable and will be reflected back in
        #     the response.
        #  @yieldparam **kwargs [Hash] the JSON_RPC named arguments
        #  @yieldreturn [Object] the response object
        # @return [Subscription, ConcurrentMonitor::Barrier]
        # @note Request messages must have content_type property set to 'application/json' or they will be ignored.
        def json_rpc_service(*topics, **response_opts, &receiver)
          receiver_obj = topics.shift unless receiver
          response(*topics, **response_opts) do |mqtt_topic, payload, content_type: nil, user_properties: {}, **|
            rpc_options = { content_type: content_type, mqtt_topic:, mqtt_properties: user_properties }

            result = JsonRpcKit::Service.serve(payload, receiver_obj, **rpc_options, &receiver)
            [result, { content_type: 'application/json', user_properties: }]
          end
        end
      end
    end
  end
end
