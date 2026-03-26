# frozen_string_literal: true

require 'English'
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
        # @!macro [new] context_params
        #   @param topics [Array<String>] additional, absolute, topic filters for requests sent with custom
        #     response_topic
        #   @param pub_opts [Hash] default options for publishing requests
        #   @option pub_opts :qos [Integer] QoS level for sending requests.
        #     If not provided will use 2 (at most once), if available, since we don't want the request processed twice
        #   @option pub_opts:user_properties [#to_a<String,String>] {V5::Packet::Publish#user_properties}
        #   @param sub_opts [Hash] options for the response subscription
        #   @option sub_opts :max_qos [Integer] Max/Requested QoS level for response subscription.
        #     If not provided will use 1 (at least once), if available, since duplicate responses are ignored anyway
        #   @option sub_opts :no_local [Boolean] {V5::Packet::Subscribe::TopicFilter#no_local}
        #   @option sub_opts :retain_handling [Integer] (default = 2) {V5::Packet::Subscribe::TopicFilter#retain_handling}
        #   @option sub_opts :retain_as_published [Boolean] {V5::Packet::Subscribe::TopicFilter#retain_as_published}
        #   @option sub_opts:user_properties [#to_a<String,String>] {V5::Packet::Subscribe#user_properties}

        # Base error class for Request/Response operations
        class Error < MQTT::Error; end

        # Default timeout error for requests
        class TimeoutError < MQTT::TimeoutError; end

        # Request/Response Context
        #
        # Manages the client side, tracking request correlation data and starting a Subscription for
        # receiving responses and completing requests.
        class Context
          # We need to synchronize access to the hash and correlation_data generation.
          include ConcurrentMonitor

          # @return [Client]
          attr_reader :client

          # @return [String] the topic prefix for responses
          attr_reader :response_base

          # @return [Hash] default options for publishing requests
          attr_reader :pub_opts

          # @return [Hash] default options for subscribing to responses
          attr_reader :sub_opts

          # @param client [Client]
          # @param response_base [String] the base topic prefix for receiving responses
          # @!macro context_params
          # @raise [QosNotSupported] if pub_qos or sub_qos are greater than supported by client
          def initialize(client, response_base, *topics, pub_opts: {}, sub_opts: {})
            @client = client
            @response_base = response_base
            @correlation_id = 0
            @req_pending = {}
            @monitor = @client.new_monitor

            client.validate_qos!(pub_opts[:qos] ||= [client.max_qos, 2].min)
            client.validate_qos!(sub_opts[:max_qos] ||= [client.max_qos, 1].min)
            @pub_opts = pub_opts
            @sub_opts = sub_opts

            topics.unshift("#{@response_base}/#")

            sub_opts[:retain_handling] ||= 2
            @subscription, @sub_task = subscribe_responses(*topics, **sub_opts)
          end

          # The default &resolver proc for #{request}
          #
          #   Returns the payload or raises error if something went wrong
          DEFAULT_RESOLVER = ->(**, &response) { response.call }

          # @!macro [new] context_request
          #  @param topic [String] the topic that is listening for requests
          #  @param payload [String] the request payload
          #  @param request_opts [Hash] additional `PUBLISH` options for the request
          #  @option request_opts :response_topic [String] override the response topic
          #    (must match the context's subscription)
          #  @option request_opts :qos [Integer] override the QoS level for publishing the request
          #  @option request_opts :user_properties [Array<(String,String)>  optional user properties
          #  @option request_opts :content_type: [String] optional content_type
          #  @option request_opts :message_expiry_interval [Integer]
          #  @yield [content_type: nil, user_properties: [], &response] an optional block used to resolve the response
          #  @yieldparam content_type [String|nil]
          #  @yieldparam user_properties [Array<[String,String]>]
          #  @yieldparam response [Proc] a callback to retrieve the response payload (String) or raise an error
          #
          #    Specifically raises a {TimeoutError} if this context is unsubscribed or its {Client} is disconnected
          #    prior to a response being received
          #  @yieldreturn [Object] the result, or raise an error

          # @overload request(topic, payload, future: false, **request_opts, &resolver)
          #  Make a request and wait for the response.
          #  @!macro context_request
          #  @param future [Boolean] return a future instead of waiting
          #  @return [Object] the response object, converted by the block if provided
          #  @return [ConcurrentMonitor::Future] if future is true
          #  @raise [TimeoutError] if message_expiry_interval was set in pub_opts, and the response times out
          #  @raise [StandardError] other errors in dispatching the request or processing the response
          def request(topic, payload, future: false, **pub_opts, &resolver)
            f, correlation_data, timeout = correlated_future(topic, payload, **@pub_opts, **pub_opts, &resolver)
            return f if future
            return f.value if f.wait(timeout)

            resolver ? resolver.call { raise TimeoutError } : raise(TimeoutError)
          ensure
            synchronize { @req_pending&.delete(correlation_data) } unless future
          end

          # Sugar to call {Client#publish} directly without a :response_topic (eg json-rpc notifications)
          # @return [void]
          def notify(topic, payload, **)
            @client.publish(topic, payload, **@pub_opts, **)
          end

          # Unsubscribe from responses
          #
          # Any pending requests will be completed with a {TimeoutError}
          # @return [void]
          def unsubscribe
            @subscription&.unsubscribe
            @sub_task&.join
          end

          # Sugar to create an endpoint to send JSON-RPC requests using this context. See {JsonRpc#json_rpc_endpoint}
          # @return [JsonRpcKit::Endpoint]
          def json_rpc_endpoint(topic, **)
            @client.json_rpc_endpoint(topic, request_context: self, **)
          end

          private

          def next_correlation_data
            # base 36 of our object id and request counter, binary
            "#{object_id.to_s(36)}-#{(@correlation_id += 1).to_s(36)}".b
          end

          def correlated_future(topic, payload, response_topic: nil, **pub_opts, &resolver)
            resolver ||= DEFAULT_RESOLVER

            if response_topic && !@subscription.match_topic?(response_topic)
              raise Error, "Custom response_topic '#{response_topic}' not covered by subscription"
            end

            response_topic ||= "#{@response_base}/#{topic}"

            future = new_future
            correlation_data =
              synchronize do
                raise Error, 'Request/Response context terminated' unless @req_pending

                next_correlation_data.tap { |cd| @req_pending[cd] = { future:, resolver: } }
              end

            @client.publish(topic, payload, **pub_opts, correlation_data:, response_topic:)

            [future, correlation_data, pub_opts[:message_expiry_interval]]
          end

          # Subscribe to response base to fulfill requests
          def subscribe_responses(*topics, **sub_opts)
            sub = @client.subscribe(*topics, **sub_opts)
            task = @client.async do
              sub.each do |_topic, payload, correlation_data: nil, **response_attr|
                next unless (caller = synchronize { @req_pending.delete(correlation_data) })

                resolve_response(caller) do |future:, resolver:|
                  future.resolve { resolver.call(correlation_data:, **response_attr) { payload } }
                end
              end
            rescue StandardError => e
              # At this point we know our pending responses are never going to be completed, so TimeoutError
              # indicates that the result of the request is unknown.
              raise TimeoutError, "Response subscription terminated due to #{e.message}"
            ensure
              # A clean disconnect of the client will terminate the enumeration, but we still need to cancel the
              # pending futures.
              cancel_pending($ERROR_INFO || TimeoutError.new('Response subscription terminated'))
            end
            [sub, task]
          end

          def resolve_response(caller)
            yield(**caller)
          end

          def cancel_pending(error)
            synchronize do
              @req_pending&.each_value do |caller|
                resolve_response(caller) { |future:, resolver:| future.resolve { resolver.call { raise error } } }
              end
              @req_pending = nil
            end
          end
        end

        # Make a {Context#request} using the {#default_request_context}
        # @return [Object]
        # @see Context#request
        def request(...)
          default_request_context.request(...)
        end

        # Create a custom request/response context
        # @param response_base [String] the context name. Used, by default, as a suffix to {Session.response_base}
        # @param absolute [Boolean] if set, treat `response_base` as an absolute topic path.
        # @!macro context_params
        # @return [RequestResponse::Context]
        # @raise [MQTT::Error] unless `:request_response_information` was sent to `CONNECT` or using `absolute` option
        def new_request_context(response_base, *topics, absolute: false, pub_opts: {}, sub_opts: {})
          response_base = "#{session.response_base!}/#{response_base}" unless absolute
          RequestResponse::Context.new(self, response_base, *topics, pub_opts:, sub_opts:)
        end

        # Get the default request/response context
        #
        #  This method is memoised but the first call during the `on_birth` handler can pass additional topics or
        #  override the default QoS settings as necessary.
        # @!macro context_params
        # @return [RequestResponse::Context]
        # @raise [MQTT::Error] unless `:request_response_information` was sent to `CONNECT`
        def default_request_context(*topics, pub_opts: {}, sub_opts: {})
          synchronize { @default_request_context ||= current_task }

          if @default_request_context == current_task
            begin
              @default_request_context = new_request_context('default', *topics, pub_opts:, sub_opts:)
            rescue StandardError => e
              @default_request_context = e
            end
          else
            wait_until(delay: 0.1, timeout: 5) do
              [Context, StandardError].any? { |klass| @default_request_context.is_a?(klass) }
            end
          end
          raise @default_request_context if @default_request_context.is_a?(StandardError)

          @default_request_context
        end

        # Establish a response subscription. Listen for requests, Serve responses.
        # @param topics [Array<String>] the topic(s) to listen for requests
        # @param sub_opts [Hash] additional properties for {V5::Packet::Subscribe}
        # @option sub_opts :max_qos [Integer] Maximum QoS level for the request subscription.
        #
        #   If not provided will use 2 (exactly once), if available, since we don't want to process a request twice
        # @param pub_opts [Integer] default options for publishing responses
        # @option pub_opts :qos [Integer] QoS level for sending responses (can be overridden by the &handler block)
        #
        #   If not provided will use 1 (at least once), if available, since we expect the caller to handle duplicates
        # @param workers [Integer] number of concurrent workers to process requests
        # @yield [topic, payload, **attr] &handler the received PUBLISH request,
        #  {V5::Packet::Publish#deconstruct_message deconstructed}
        # @yieldparam topic the topic the request was received on
        # @yieldparam payload [String] the request payload
        # @yieldparam :content_type [String<UTF8>] (optional)
        # @yieldparam :user_properties [Array<(String<UTF8>, String<UTF8>)>] (optional)
        # @yieldparam :message_expiry_interval [Integer] (optional) the **remaining** message expiry
        #
        #   If the handler does not finish within this time, and does not provide a positive :message_expiry_interval
        #   in the response callback, then the response will be silently discarded. The handler can
        #   respond with a nil payload and a zero :message_expiry_interval to indicate it has abandoned processing.
        #
        # @yieldparam :qos [Integer] (informational)
        # @yieldparam :retain [Boolean] (informational)
        # @yieldreturn [[String, Hash<Symbol>]] the response payload and optional attributes for response `PUBLISH`
        # @return [[Subscription,ConcurrentMonitor::Barrier]]
        #   the subscription handling requests and a barrier containing the worker tasks
        # @note Handler exceptions are logged at ERROR level and do not propagate
        def response(*topics, pub_opts: {}, sub_opts: {}, workers: 1, barrier: nil, &handler)
          barrier ||= new_barrier
          validate_qos!(pub_opts[:qos] ||= [max_qos, 1].min)
          validate_qos!(sub_opts[:max_qos] ||= [max_qos, 2].min)

          [subscribe(*topics, **sub_opts), barrier].tap do |sub, b|
            workers.times { |_i| handle_requests(sub, b, **pub_opts, &handler) }
          end
        end

        private

        # We allow outgoing publish to set content_type, user_properties, qos (override default)
        def handle_requests(sub, barrier, **pub_opts, &handler)
          sub.async(via: barrier) do |topic, request_payload, message_expiry_interval: nil, **request_attr|
            expiry_clock = ConcurrentMonitor::TimeoutClock.timeout(message_expiry_interval)
            handle_request(topic, request_payload, handler:, **request_attr) do |response_payload, **response_attr|
              pub_opts = build_response_publish_opts(pub_opts:, response_attr:, expiry_clock:)
              publish_response(response_payload, pub_opts, **request_attr)
            rescue StandardError => e
              log_failed_response('callback', e, **request_attr)
            end
          end
        end

        def build_response_publish_opts(expiry_clock:, pub_opts:, response_attr:)
          # The handler response options override the original pub_opts, except for user_props which are merged
          pub_opts = pub_opts.merge(response_attr) do |key, old, new|
            key == :user_properties ? (old.to_a + new.to_a).uniq : new
          end

          # Set expiry interval to original minus however long it took to process,
          if (remaining = expiry_clock.remaining&.ceil) && !pub_opts.key?(:message_expiry_interval)
            pub_opts[:message_expiry_interval] = remaining
          end

          pub_opts
        end

        # @return [void] this always calls the publish callback, so we are done after this.
        def handle_request(topic, request_payload, handler:, **request_attr, &response_callback)
          called = false
          response_payload, response_attr =
            handler.call(topic, request_payload, **request_attr) do |response_payload, **response_attr|
              response_callback.call(response_payload, **response_attr).tap { called = true }
            end

          # Already called, or will be called asynchronously
          return if called || response_payload == :callback

          # return synchronously
          response_callback.call(response_payload, **response_attr || {})
        rescue StandardError => e
          # This is the handler.call raising error (since our response callback logs and swallows errors)
          log_failed_response('handler', e, **request_attr)
        end

        def publish_response(response_payload, response_attr, response_topic: nil, correlation_data: nil, **_)
          return unless response_topic && correlation_data

          if (expiry = response_attr[:message_expiry_interval]) && expiry && !expiry.positive?
            log.warn "skipping expired(#{expiry}) response(#{correlation_data})"
            return
          end

          # Use empty string if you want to send back an empty payload.
          raise ArgumentError, "No payload for response(#{correlation_data})" if response_payload.nil?

          publish(response_topic, response_payload.to_s, **response_attr, correlation_data:, response_topic: nil)
        end

        def log_failed_response(from, error, correlation_data: nil, response_topic: nil, **_)
          # There is no point killing an async worker task
          # Handler really should encapsulate its errors
          log.error("response #{from} failed: #{correlation_data}@#{response_topic}")
          log.error(error)
          nil
        end

        def cancel_session(*)
          # The default request_context will be dead after session is cancelled
          synchronize { @default_request_context = nil }
          super
        end

        def birth_complete!
          # Force start the default request/response context subscription if :request_response_information
          default_request_context if session.response_base
          super
        end
      end
    end
  end
end
