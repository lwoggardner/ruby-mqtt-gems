# frozen_string_literal: true

require 'json_rpc_kit'
require_relative 'request_response'

module MQTT
  module V5
    class Client < MQTT::Core::Client
      # JSON-RPC over MQTT v5 Request/Response
      module JsonRpc
        # A stopped task means we timed out, which means there is no point sending a response which in json-rpc
        # land is the same as having a notification that needs no response
        module RescueStopped
          def value
            super
          rescue ConcurrentMonitor::TaskStopped
            nil
          end
        end

        # Build up user properties, unless explicitly set to nil.
        ENDPOINT_MERGE =
          proc do |k, old, new|
            case k
            when :user_properties
              # up can be hash or array of pair
              new ? (old.to_a + new.to_a).uniq : []
            else
              new
            end
          end

        # Create JSON-RPC Client endpoint over MQTT Request Response
        #
        # @param topic [String] the MQTT topic that will response to JSON-RPC requests
        # @param request_context [RequestResponse::Context]
        # @param defaults [Hash] default publish options for JSON-RPC requests
        # @option defaults :response_topic [String] override the response topic
        #    (must match the context's subscription)
        # @option defaults :qos [Integer] override the QoS level for publishing the request
        # @option defaults :user_properties [Array<(String,String)>  optional user properties
        # @option defaults :timeout [Integer] optional timeout for requests
        # @return [JsonRpcKit::Endpoint] a client for invoking JSON-RPC methods
        # @example
        #   endpoint = client.json_rpc_endpoint('service/hello', qos: 1)
        #
        #   # Send '{ "id" : "xxx-yyy", "method": "hello", "params" : ["world" ] }' to "service/hello" topic with qos: 1
        #   endpoint.hello('world') #=> 'Hello world!' - waits and returns response.
        #
        #   # Send '{"method": "hello", "params" : ["you" ] }' to "service/hello" topic with qos: 0
        #   endpoint.hello!('you') #=> nil - notification, did not wait for a response
        #
        #   # With default response options
        #   endpoint.with(qos: 2, timeout: 10).hello('world')
        #
        #   # Trace with user properties
        #   trace = endpoint.with(mqtt_user_properties: { 'request-trace-id' => 'tx1234' }).with_conversion do
        #   | mqtt_user_properties: [], **_, &result|
        #     log.trace { mqtt_user_properties.to_h['response-trace-id'] }
        #     result.call
        #   end
        #   trace.hello('trace') #> sends request trace, logs response trace
        def json_rpc_endpoint(topic, request_context: default_request_context, **defaults)
          JsonRpcKit.endpoint(
            **defaults, prefix: 'mqtt_', filter: %i[qos retain user_properties], merge: ENDPOINT_MERGE
          ) do |id, request_json, async: false, timeout: nil, **request_opts, &response|
            request_opts[:message_expiry_interval] ||= timeout if timeout
            next request_context.notify(topic, request_json, **request_opts) unless id

            request_context.request(topic, request_json, future: async, **request_opts) do |**resp_opts, &mqtt_response|
              json_rpc_resolver(response, **resp_opts, &mqtt_response)
            end
          end
        end

        # Merge proc for reducing multiple response options retrieved from individual requests in a batch
        SERVICE_MERGE =
          proc do |k, old, new|
            case k
            when :qos then [old, new].max
            when :user_properties then ((old || []).to_a + (new || []).to_a).uniq
            else new
            end
          end

        # rubocop:disable Metrics/ParameterLists,Metrics/MethodLength

        # Create a JSON-RPC service handler over MQTT Request/Response.
        #
        # Subscribes to MQTT topics and processes incoming JSON-RPC requests, sending responses back
        # via the MQTT response mechanism. Supports asynchronous task spawning with timeout management.
        #
        # @param topics [Array<String>] MQTT topics to subscribe to for JSON-RPC requests
        # @param workers [Integer] Number of concurrent workers processing requests (default: 1)
        # @param async [ConcurrentMonitor, nil, false] Controls asynchronous execution:
        #   - `self` (default): Use client's monitor for async task spawning with timeout support
        #   - `ConcurrentMonitor`: Custom monitor for async task spawning
        #   - `nil` or `false`: Synchronous execution (no timeout support)
        # @param async_policy [Boolean, #call, nil] Describes which methods would benefit from async execution
        #   (see {JsonRpcKit::Service#json_rpc_async?})
        # @param service [#json_rpc_call, nil] Service implementation object
        # @param pub_opts [Hash] Default MQTT publish options for responses (qos, user_properties, etc.)
        # @yield [request_opts, response_opts, id, method, *args, **kwargs] Service handler
        #   (see {JsonRpcKit::Service#json_rpc_call})
        # @return [Subscription] MQTT subscription handling JSON-RPC requests
        #
        # @example Basic service
        #   client.json_rpc_service('rpc/calculator') do |request_opts, response_opts, id, method, *args|
        #     case method
        #     when 'add' then args.sum
        #     when 'multiply' then args.reduce(:*)
        #     end
        #   end
        #
        # @example With service object
        #   class Calculator
        #     include JsonRpcKit::Service
        #     json_rpc :add
        #     def add(*numbers) = numbers.sum
        #   end
        #
        #   client.json_rpc_service('rpc/calculator', service: Calculator.new)
        #
        # @example With async policy
        #   client.json_rpc_service('rpc/service', async_policy: true) do |_, _, id, method, *args|
        #     # All methods will be spawned asynchronously
        #     expensive_operation(method, *args)
        #   end
        def json_rpc_service(
          *topics,
          workers: 1, pub_opts: {}, sub_opts: {},
          async: self, async_policy: nil, service: nil, &service_proc
        )
          barrier = new_barrier
          watcher =
            (ConcurrentMonitor::TimeoutWatcher.new(monitor: async).tap { barrier.async(&:run) } if async)

          transport_proc =
            JsonRpcKit::Service.transport(
              prefix: 'mqtt_', filter: %i[qos user_properties], merge: SERVICE_MERGE,
              async: watcher && json_rpc_transport_async, async_policy:,
              service:, &service_proc
            )

          response(*topics, workers:, barrier:, sub_opts:, pub_opts:) do |topic, payload, **request_attr, &callback|
            request_attr.merge!(topic:, watcher:)

            transport_proc.call(payload, request_attr) do |response_json, response_attr|
              callback.call(response_json, **response_attr)
            end

            :callback
          end
        end

        # rubocop:enable Metrics/MethodLength
        private

        # @!visibility private
        # TaskSpawner implementing the Full Control Interface for JSON-RPC over MQTT.
        #
        # Spawns tasks with timeout management via TimeoutWatcher and barrier synchronization
        # for batch requests. Returns nil for synchronous execution when no watcher is available
        # or when async hints indicate synchronous execution is preferred.
        def json_rpc_transport_async
          proc do |name, opts, **context, &task|
            next nil unless opts[:watcher]

            case name
            when :batch
              next nil unless context[:async_count].positive?

              opts[:barrier] = opts[:watcher].new_barrier
              json_rpc_batch_task(**context, **opts, &task)
            when :request
              next nil unless context[:async]

              json_rpc_request_task(**context, **opts, &task)
            end
          end
        end

        def json_rpc_request_task(
          watcher:, barrier: nil, id: nil, method: nil, correlation_data: nil, message_expiry_interval: nil, **, &task
        )
          name = "JSON-RPC(#{id || '<nil>'},#{method},#{correlation_data})"

          # if we have barrier then this is a batch task, otherwise an outer request task
          (barrier ? barrier.async(name:, &task) : watcher.with_timeout(message_expiry_interval, name:, &task))
            .extend(RescueStopped)
        end

        # rubocop:enable Metrics/ParameterLists

        def json_rpc_batch_task(watcher:, barrier:, correlation_data: nil, message_expiry_interval: nil, **, &task)
          name = "JSON-RPC Batch(#{correlation_data})"
          watcher.with_timeout(message_expiry_interval, name:) { barrier.wait!(&task) }
        end

        def json_rpc_resolver(response_callback, **response_options, &mqtt_response)
          response_callback.call(**response_options) do
            mqtt_response.call
          rescue MQTT::TimeoutError => e
            raise JsonRpcKit::TimeoutError, e.message
          end
        end
      end
    end
  end
end
