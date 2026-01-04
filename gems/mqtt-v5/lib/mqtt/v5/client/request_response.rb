# frozen_string_literal: true

require_relative 'json_rpc'
require_relative '../client'

module MQTT
  module V5
    class Client < Core::Client
      # This module implements the MQTT V5 Request/Response protocol.
      #
      # @example sending requests
      #  # Request broker to negotiate a response topic prefix, and automatically establish the default request context,
      #  # subscribed to the response base topic prefix.
      #  client.connect(request_response_information: true)
      #
      #  # Then make requests...
      #  result = client.request('service/hello', 'world') # => 'Hello world'
      #
      # @example serving responses
      #  client.response('service/hello') do |topic, request_payload|
      #    "Hello #{request_payload}"
      #  end
      # @see https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901252
      module RequestResponse
        # Base error class for Request/Response operations
        class Error < MQTT::Error; end

        # Default timeout error for requests
        class TimeoutError < MQTT::TimeoutError; end

        # Request/Response Context
        #
        # Manages the client side, tracking request correlation data and starting a Subscription for
        # receiving responses and completing requests.
        class Context
          attr_reader :client, :response_base, :pub_qos

          # @param client [Client]
          # @param response_base [String] the base topic prefix for receiving responses
          # @param topics [Array<String>] additional topics to subscribe to for requests with custom response_topic
          # @param pub_qos [Integer] QoS level for sending requests
          # @param sub_qos [Integer] QoS level for response subscription
          def initialize(client, response_base, *topics, pub_qos: 0, sub_qos: pub_qos)
            @client = client
            @response_base = response_base
            @pub_qos = pub_qos
            @correlation_id = 0
            @req_pending = {}

            topics.unshift("#{@response_base}/#")
            @subscription, @sub_task = subscribe_responses(*topics, max_qos: sub_qos)
          end

          # @!macro [new] request
          # @param topic [String] the topic that is listening for requests
          # @param payload [String] the request payload
          # @param correlation_data [String] override the correlation data
          # @param response_topic [String] override the response topic (must match the context's subscription)
          # @param qos [Integer] override the QoS level for publishing the request
          # @yield(response) an optional block used to resolve the future.
          # @yieldparam response [String] the response payload
          # @yieldreturn [Object]# Make a request and return immediately (after QoS completion)

          # rubocop:disable Metrics/ParameterLists

          # Make a request and return immediately (after QoS completion for PUBLISH)
          # @!macro request
          # @return [ConcurrentMonitor::Future] The future that will be resolved by the response.
          def future(
            topic, payload,
            correlation_data: next_correlation_data, response_topic: nil, qos: @pub_qos,
            **,
            &resolver
          )
            correlation_data = correlation_data.b

            if response_topic && !@subscription.match_topic?(response_topic)
              raise Error, "Custom response_topic '#{response_topic}' not covered by subscription"
            end

            response_topic ||= "#{@response_base}/#{topic}"

            @client.new_future.tap do |future|
              @req_pending[correlation_data] = { future:, resolver: }
              @client.publish(topic, payload, correlation_data:, response_topic:, qos:, **)
            end
          end

          # Make a request and wait for the response.
          # @!macro request
          # @param timeout[Numeric] for waiting on the future
          # @param exception [Class] the exception to raise on timeout
          # @return [Object] the response object (converted by the block if given)
          # @raise [TimeoutError, exception] if the request times out
          def request(
            topic, payload,
            correlation_data: next_correlation_data, timeout: nil, exception: TimeoutError,
            **, &
          )
            future(topic, payload, correlation_data:, **, &).value(timeout:, exception:)
          ensure
            @req_pending.delete(correlation_data.b)
          end

          # rubocop:enable Metrics/ParameterLists

          # Publish directly (eg json-rpc notifications)
          def notify(topic, payload, qos: @pub_qos, **)
            @client.publish(topic, payload, qos:, **)
          end

          # Unsubscribe from responses and stop processing
          def unsubscribe
            @subscription&.unsubscribe
            @sub_task&.join
          end

          # @!visibility private
          # return [String<UTF-8>]
          def next_correlation_data
            "#{@client.current_task.object_id}-#{@correlation_id += 1}"
          end

          # Create an endpoint to send JSON-RPC requests using this context
          # @return [JsonRpc::Endpoint]
          # @param defaults [Hash] default publish options for JSON-RPC requests (eg qos:)
          def json_rpc_endpoint(topic, **defaults)
            @client.json_rpc_endpoint(topic, request_context: self, **defaults)
          end

          private

          # Subscribe to response base to fulfill requests
          # @param topics [Array<String>] topics to subscribe to (defaults to response_base/#)
          # @param max_qos [Integer] maximum QoS level for subscription
          def subscribe_responses(*topics, max_qos: [@client.max_qos, 1].min)
            @client.subscribe(*topics, max_qos:).async do |_topic, payload, correlation_data: nil, **opts|
              next unless (caller = @req_pending.delete(correlation_data))

              future, resolver = caller.values_at(:future, :resolver)
              future.resolve { resolver ? resolver.call(payload, **opts) : payload }
            end
          end
        end

        # Make a request using the default request/response context, created in response to
        # providing `:request_response_information` to CONNECT.
        # @return [Object]
        # @see Context#request
        def request(...)
          default_request_context.request(...)
        end

        # Make a request using the default request/response context, return immediately
        # @return [ConcurrentMonitor::Future]
        # @see Context#future
        def request_future(...)
          default_request_context.future(...)
        end

        # Establish a response subscription. Listen for requests, Serve responses.
        # @param topics [Array<String>] the topic(s) to listen for requests on
        # @param pub_qos [Integer] QoS level for sending responses
        # @param sub_qos [Integer] QoS level for subscription
        # @param workers [Integer] number of concurrent workers to process requests
        # @yield [topic, payload, **attr] processes request and return response
        # @yieldreturn [String<UTF8>] the response
        # @return [Subscription,ConcurrentMonitor::Barrier]
        #   the subscription handling requests and a barrier containing the worker tasks
        def response(*topics, pub_qos: 0, sub_qos: pub_qos, workers: 1, &handler)
          [subscribe(*topics, max_qos: sub_qos), new_barrier].tap do |sub, barrier|
            workers.times do |_i|
              sub.async(via: barrier) do |topic, payload, response_topic: nil, correlation_data: nil, **attrs|
                response_payload, response_attrs = handler.call(topic, payload, **attrs)
                next unless response_topic && correlation_data

                response_attrs ||= {}
                publish(response_topic, response_payload.to_s, qos: pub_qos, **response_attrs, correlation_data:)
              end
            end
          end
        end

        # Create a custom request/response context
        # @param response_base [String] the context name. Used, by default, as a suffix to {Session.response_base}
        # @param absolute [Boolean] if set, treat `response_base` as an absolute topic path.
        # @param topics [Array<String>] additional topics to subscribe to for requests with custom response_topic.
        # @param context_opts [Hash] for #{Context#initialize}
        # @return [RequestResponse::Context]
        # @raise [MQTT::Error] unless `:request_response_information` was sent to `CONNECT` or using `absolute` option
        def new_request_context(response_base, *topics, absolute: false, **context_opts)
          response_base = "#{session.response_base!}/#{response_base}" unless absolute
          RequestResponse::Context.new(self, response_base, *topics, **context_opts)
        end

        # Get the default request/response context
        # @param sub_qos [Integer] QoS level for subscription (only valid on first during `on_birth` event.
        # @return [RequestResponse::Context]
        # @raise [MQTT::Error] unless `:request_response_information` was sent to `CONNECT`
        def default_request_context(sub_qos: nil)
          @default_request_context ||=
            new_request_context('default', sub_qos: sub_qos || [session.max_qos, 1].min)
        end

        private

        def birth_complete!
          # Force start the default request/response context subscription
          default_request_context if session.response_base
          super
        end
      end
    end
  end
end
