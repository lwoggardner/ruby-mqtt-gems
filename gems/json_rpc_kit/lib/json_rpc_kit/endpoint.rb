# frozen_string_literal: true

require_relative 'transport_options'

module JsonRpcKit
  # @!group Implementation and Documentation Notes
  #  **Batch vs Endpoint Pattern**:
  #    - Batch separates "add request" (json_rpc_request) from "invoke" (json_rpc_invoke)
  #    - Endpoint combines request+invoke in single methods (json_rpc_invoke)
  #
  #  **Static vs Instance Methods**:
  #    - Where an instance method (Endpoint or Batch) calls a corresponding class method
  #    - Keep parameter descriptions identical between static and instance versions
  #
  #  ** Documentation**:
  #    - do not use YARD macros it is too complex, and we can dedup with other tools or AI.
  #    - parameters with common intent across similar methods described above, should have identical descriptions
  #      across all usages unless there is a specific difference that is noted.
  # @!endgroup

  # An endpoint for dispatching JSON-RPC requests via ruby calls.
  #
  # This class covers the JSON-RPC generation of ids and encoding/decoding of method and parameters while delegating
  # the send/receive of JSON encoded data to a {.transport} proc.
  #
  # Requests can be sent individually via
  # * the class method {.invoke}
  # * the instance method {#json_rpc_invoke}
  # * dynamic method call (via {#method_missing} )
  #
  # or as a {Batch}
  #
  # ### Composability
  #
  # Endpoints can be configured and composed using {InstanceHelpers#initialize .new} and {#with}
  # Conventionally supported options include `:async` and `:timeout`, plus any transport-specific options:
  #
  # ### Asynchronous Operations
  #
  # Async operations return transport-specific futures/promises instead of blocking:
  #
  # @example Basic Usage
  #   # Create an endpoint with optional namespace
  #   endpoint = JsonRpcKit::Endpoint.new(namespace: 'api.v1') do |id, request_json, **opts, &response|
  #     # Your transport implementation here
  #     http_response = HTTP.post('http://api.example.com/rpc', json: request_json)
  #     response.call { http_response.body.to_s }
  #   end
  #
  #   # Call methods directly - returns the result from the JSON-RPC response
  #   result = endpoint.get_user(id: 123)
  #
  # @example Dynamic method calls (recommended)
  #   result = endpoint.get_user(id: 123)
  #   # => {"name"=>"Alice", "id"=>123} via {"jsonrpc":"2.0","method":"api.v1.getUser","params":{"id":123},"id":"abc-1"}
  #
  #   # Named parameters
  #   endpoint.update_user(id: 123, name: 'Alice')
  #   # via {"jsonrpc":"2.0","method":"api.v1.updateUser","params":{"id":123,"name":"Alice"},"id":"abc-2"}
  #
  #   # Positional parameters
  #   endpoint.calculate(10, 20, 'add')
  #   # => 30 via {"jsonrpc":"2.0","method":"api.v1.calculate","params":[10,20,"add"],"id":"abc-3"}
  #
  # @example Explicit JSON-RPC calls (for advanced control)
  #   result = endpoint.json_rpc_invoke({}, :next_id, 'users.v1.getUser', id: 123)
  #
  # @example Notifications (fire-and-forget, no response expected)
  #   # Bang method syntax
  #   endpoint.log_event!('User updated')
  #   # => nil via {"jsonrpc":"2.0","method":"api.v1.logEvent","params":["User updated"]}
  #
  #   # Explicit notify
  #   endpoint.json_rpc_notify(:log_event, message: 'User updated')
  #   # => nil via {"jsonrpc":"2.0","method":"api.v1.logEvent","params":{"message":"User updated"}}
  #
  #   # Via json_rpc_invoke with nil id
  #   endpoint.json_rpc_invoke({}, nil, 'system.logEvent', message: 'User updated')
  #   # => nil via {"jsonrpc":"2.0","method":"system.logEvent","params":{"message":"User updated"}}
  #
  # @example Result conversion and error handling
  #   user = endpoint.get_user(id: 123) do |**, &result|
  #     User.from_json(result.call)
  #   rescue JsonRpcKit::Error => e
  #     raise NotFoundError, "User not found" if e.code == -32001
  #     raise
  #   end
  #   # => User object or raises NotFoundError for specific error codes
  #
  # @example Asynchronous calls
  #   # one-shot context
  #   future = endpoint.with(async: true).get_user(id: 123) # returns future immediately
  #   # .. do some other things...
  #   result = future.value # blocks until complete
  #
  #   # with more control over method naming
  #   future = endpoint.json_rpc_async(:next_id, 'users.v2.getUser', id: 123)
  #
  #   # async context for multiple calls
  #   async_endpoint = endpoint.with(async: true)
  #   future1 = async_endpoint.get_user(id: 123)
  #   future2 = async_endpoint.get_user_perms(id: 123)
  #
  #   result = User.new(data: future1.value, perms: future2.value)
  #
  # @example Creating specialized contexts with smart merging
  #   # Create endpoint with custom ID generator
  #   uuid_generator = ->() { SecureRandom.uuid }
  #   api_endpoint = JsonRpcKit::Endpoint.new(next_id: uuid_generator) do |id, json, **opts, &response|
  #     # transport implementation using opts for timeout, headers, etc.
  #   end
  #
  #   # Create context with base headers
  #   authed_endpoint = api_endpoint.with(headers: {'X-Auth': 'token'})
  #
  #   # Smart merge: headers are merged (Hash), timeout is replaced
  #   authed_endpoint.with(timeout: 30, headers: {'X-Request-ID': '123'}).get_user(id: 1)
  #   # opts passed to transport: {headers: {'X-Auth': 'token', 'X-Request-ID': '123'}, timeout: 30}
  #
  #   # Arrays are concatenated
  #   tagged = api_endpoint.with(tags: ['api', 'v1'])
  #   tagged.with(tags: ['user']).get_user(id: 1)
  #   # opts passed to transport: {tags: ['api', 'v1', 'user']}
  #
  # @example Result conversion
  #   # Convert errors
  #   not_found_endpoint = api_endpoint.with_conversion do |**, &result|
  #     result.call
  #   rescue JsonRpcKit::Error => e
  #     raise NotFoundError if e.code == -32_001
  #     raise
  #   end
  #
  #   # Convert results based on response metadata
  #   typed_endpoint = api_endpoint.with_conversion do |resp_headers: {}, **, &result|
  #     case resp_headers['X-Result-Type']
  #     when 'User'
  #        User.from_json(result.call)
  #     else
  #       result.call
  #     end
  #   end
  class Endpoint
    # @!visibility private
    # Common static class methods for Endpoint and Endpoint::Batch
    module ClassHelpers
      include Helpers

      # Build JSON-RPC request object
      # @return [Hash] compact request object
      def to_request(id, method, args, kwargs)
        raise ArgumentError, 'Use either positional or named parameters, not both' if args.any? && kwargs.any?

        if kwargs.keys.any? { |k| k.start_with?('rpc_') }
          raise ArgumentError, "Invalid arguments for batch request: #{kwargs.keys}"
        end

        params = nil
        params = args if args.any?
        params = kwargs if kwargs.any?

        { jsonrpc: '2.0', method: method, params: params, id: id }.compact
      end

      # Handle JSON-RPC response object (Hash)
      # @return [Object] the result or raises error
      def from_response(response)
        return response[:result] unless response[:error]

        Error.raise_error(**response[:error])
      end

      # Ensure response errors are JsonRpcKit errors.
      def call_response(&response_json)
        response_json.call
      rescue Error
        raise
      rescue StandardError => e
        raise InvalidResponse, e.message, class_name: e.class.name
      end
    end

    # Common instance methods for {Endpoint} and {Endpoint::Batch}
    module InstanceHelpers
      # Create a JSON-RPC endpoint.
      #
      # @example Creating an endpoint with context
      #   endpoint = JsonRpcKit::Endpoint.new(namespace: 'api.v1') do |id, json, **opts, &response|
      #     # transport implementation
      #   end
      #
      #   # Create contexts for different scenarios
      #   fast_endpoint = endpoint.with(timeout: 5)
      #   slow_endpoint = endpoint.with(timeout: 30)
      #   async_endpoint = endpoint.with(async: true)
      #
      # @param namespace [String] optional namespace prefix for method names
      # @param next_id [#call] ID generator (default: DefaultIdGenerator.new)
      # @param opts [Hash] default options for requests (async, timeout) and arbitrary options specific
      #   to the underlying transport (http_headers etc)
      # @option opts [Boolean] :async (false) send requests asynchronously
      # @option opts [Numeric] :timeout (nil) timeout to wait for responses
      # @option opts :prefix,:merge,:filter,:ignore [Object] see {TransportOptions}
      # @option opts [Object] :.* arbitrary options for transport
      # @param transport [Proc] transport block for sending requests
      def initialize(namespace: nil, next_id: DefaultIdGenerator.new, **opts, &transport)
        @namespace = namespace
        @next_id = next_id
        @options_config = TransportOptions.create_from_opts(opts)
        @opts = @options_config.filter_opts(opts)
        @transport = transport
      end

      private

      def json_rpc_wrap_converter(&converter)
        return converter || DEFAULT_CONVERTER unless @opts[:converter]
        return @opts[:converter] unless converter

        # We are immutable so it is safe to use @opts[:converter]
        existing = @opts[:converter]
        proc { |**res_opts, &result| converter.call(**res_opts) { existing.call(**res_opts, &result) } }
      end

      def json_rpc_id_method(id, method)
        # Handle bang methods for notifications
        if method.is_a?(Symbol) && method.to_s.end_with?('!')
          id = nil
          method = method.to_s.chomp('!').to_sym
        end

        [
          id == :next_id ? @next_id.call : id,
          method.is_a?(Symbol) ? self.class.ruby_to_json_rpc(method, namespace: @namespace) : method
        ]
      end

      def respond_to_missing?(method, _include_private = false)
        return true unless method.end_with?('?', '=')

        super
      end
    end

    # Default ID generator using object_id and counter
    #
    # IDs are automatically generated when using dynamic method calls or when
    # passing `:next_id` to explicit JSON-RPC methods. The format is "objectid-counter"
    # ensuring uniqueness within the endpoint instance.
    class DefaultIdGenerator
      # @return [String] generated ID in format "objectid-counter"
      # @example
      #   generator = DefaultIdGenerator.new
      #   generator.call  #=> "abc123-1"
      #   generator.call  #=> "abc123-2"
      # @example Using a custom proc
      #   custom_generator = -> { SecureRandom.uuid }
      #   endpoint = JsonRpcKit::Endpoint.new(next_id: custom_generator) { |id, json, &response| ... }
      def call
        @id ||= 0
        "#{object_id.to_s(36)}-#{(@id += 1).to_s(36)}"
      end
      alias next call
    end

    # Looks like a class, is actually a proc.
    UUIDGenerator = -> { SecureRandom.uuid }

    # The default converter block (no conversion) for type conversion of JSON-RPC calls and errors
    # @see #with_conversion
    DEFAULT_CONVERTER = ->(**, &result) { result.call }

    # Batch request builder for collecting multiple JSON-RPC calls
    #
    # @example Basic Batch Usage
    #   # Create a batch from an endpoint
    #   batch = endpoint.json_rpc_batch
    #
    #   # Add requests to the batch
    #   batch.get_user(id: 1)
    #   batch.get_user(id: 2)
    #   batch.update_user(id: 3, name: 'Alice')
    #
    #   # Execute all requests
    #   results = batch.json_rpc_invoke
    #
    #   # Access individual results
    #   user1 = results[batch_id_1].call  # Returns user data or raises error
    #
    # Requests are created and added to a collection via
    # * the static class method {.request}
    # * the instance method {#json_rpc_request}
    # * dynamic method call (via {#method_missing} )
    #
    # The batch is then dispatched to the underlying transport via
    # * the static class method {.invoke}
    # * the instance method {#json_rpc_invoke}
    #
    # The result of a batch is a map of request id to a Proc that when called returns the result of the corresponding
    # request or raises its error.
    #
    # @example Working with batch results
    #   batch = endpoint.json_rpc_batch
    #   id1 = batch.get_user(id: 1)
    #   id2 = batch.get_user(id: 2)
    #
    #   results = batch.json_rpc_invoke
    #
    #   # Get successful results
    #   user1 = results[id1].call
    #
    #   # Handle errors for individual requests
    #   begin
    #     user2 = results[id2].call
    #   rescue JsonRpcKit::Error => e
    #     puts "Failed to get user 2: #{e.message}"
    #   end
    class Batch
      # Default converter for handling response options and errors for a batch
      DEFAULT_BATCH_CONVERTER = ->(**response_opts, &batch) { batch.call(**response_opts) }

      class << self
        include ClassHelpers

        # The default proc for the {invoke} result hash
        NO_RESPONSE_DEFAULT_PROC = ->(_h, id) { raise InvalidResponse, "Invalid id='#{id}' in batch response" }

        # Add a request to a batch collection
        # @overload request(batch, id, method, *args, **kwargs, &converter)
        #   @param batch [Array|#<<] a collection to add the batch request to
        #   @param id [String|Integer|Symbol|nil] request ID (:next_id for auto-generated, nil for notification)
        #   @param method [String] the JSON-RPC method name
        #   @param args [Array] positional arguments
        #   @param kwargs [Hash] named arguments
        #   @yield [**response_opts, &result] optional result converter
        #   @yieldparam result [Proc] callback to retrieve the response result or raise its error
        #   @yieldreturn [Object] the converted result, or raise a converted error
        #   @return [String|Integer|nil] the id of the request, or nil for a notification
        #   @note As per JSON-RPC spec it is an error to provide both positional and named arguments
        def request(batch, id, method, *args, **kwargs, &converter)
          converter ||= DEFAULT_CONVERTER
          id.tap { batch << { id:, request: to_request(id, method, args, kwargs), converter: } }
        end

        # Send the batch of requests with transport options
        # @overload invoke(batch, transport_opts = {}, &transport)
        #  @param batch [Array] collection filled by {request}
        #  @param transport_opts [Hash] transport options
        #  @option transport_opts :batch_converter [#call] (optional)
        #    converter to transform response options and handle the batch result or error
        #  @option transport_opts :async [Boolean] handle responses asynchronously
        #  @option transport_opts :timeout [Numeric] request timeout
        #  @option transport_opts :batch_converter [Proc] a converter to manage the batch result Hash or
        #   the single error indicating something went wrong in invoking the batch.
        #  @yield [id, request_json, **transport_opts, &transport_response]
        #    transport to send requests and handle responses
        #  @return [nil] if the batch was empty or all the requests were notifications
        #  @return [#value] a transport-specific future/promise (async operations) whose value is the response Hash
        #  @return [Hash<String|Integer, Proc>] map of ids to result proc
        def invoke(batch, transport_opts = {}, **kw_opts, &transport)
          return nil if batch.empty?

          transport_opts.merge!(**kw_opts, content_type: CONTENT_TYPE)

          # The batch converter converts the whole batch the result it receives is either the Hash result
          # or the top level error raised if the batch failed entirely. eg It can convert the response opts
          batch_converter = transport_opts.delete(:batch_converter) || DEFAULT_BATCH_CONVERTER
          batch_id, requests, converters = batch_prepare(batch)

          transport.call(batch_id, requests.to_json, **transport_opts) do
          |content_type: CONTENT_TYPE, **response_opts, &json_response|
            batch_converter.call(**response_opts) do |**converted_opts|
              batch_response(converters, **converted_opts, content_type:, &json_response)
            end
          end
        end

        private

        def yield_calls(calls)
          calls.each { |call| yield(**call) }
        end

        def batch_prepare(batch, batch_id = nil, requests: [], converters: {})
          yield_calls(batch) do |id:, request:, converter:|
            requests << request
            next unless id

            # Thread safety issue?
            raise InternalError, "Duplicate request id #{id} in batch" if converters.key?(id)

            converters[id] = converter
            batch_id ||= id # use the id of the first request we find
          end
          converters.default_proc = NO_RESPONSE_DEFAULT_PROC
          [batch_id, requests, converters]
        end

        def batch_response(converters, content_type:, **, &json_response)
          response = call_response(&json_response)

          parse_response(response, content_type:, batch: true)
            .to_h { |r| [r[:id], proc { converters[r[:id]].call(**) { from_response(r) } }] }
            .tap { |h| h.default_proc = NO_RESPONSE_DEFAULT_PROC }
        end
      end

      include InstanceHelpers

      # Create a new batch.
      # @param batch [Array] empty container for batch requests (default: [])
      # @param transport_options [Hash]
      # @param transport [Proc] transport block for sending requests
      def initialize(batch: [], **transport_options, &transport)
        raise ArgumentError 'batch must be initially empty' unless batch.empty?

        @batch = batch
        super(**transport_options, &transport)
      end

      # rubocop:disable Style/MissingRespondToMissing

      # @overload method_missing(method, *args, **kwargs, &converter)
      #  Redirects all method calls to {#json_rpc_request}
      #  @return [String|Integer|nil] the id of the request, or nil for a notification (bang! method)
      def method_missing(method, ...)
        json_rpc_request(:next_id, method, ...)
      end

      # rubocop:enable Style/MissingRespondToMissing

      # Fire and forget notification (ie does not get a response)
      # @overload json_rpc_notify(method, *args, **kwargs)
      #   @param method [Symbol|String] the RPC method to invoke (Symbol converted with ruby_to_json_rpc)
      #   @param args [Array] positional arguments
      #   @param kwargs [Hash] named arguments
      #   @return [nil]
      def json_rpc_notify(method, *, **)
        json_rpc_request(nil, method, *, **)
        nil
      end

      # Add a request to this batch
      # @overload json_rpc_request(id, method, *args, **kwargs, &converter)
      #   @param id [String|Integer|Symbol|nil] request ID (:next_id for auto-generated, nil for notification)
      #   @param method [Symbol|String] the RPC method to invoke (Symbol converted with ruby_to_json_rpc)
      #   @param args [Array] positional arguments
      #   @param kwargs [Hash] named arguments
      #   @yield [**response_opts, &result] optional result converter
      #   @yieldparam result [Proc] callback to retrieve the response result or raise its error
      #   @yieldreturn [Object] the converted result, or raise a converted error
      #   @return [String|Integer|nil] the id of the request, or nil for a notification
      #   @note As per JSON-RPC spec it is an error to provide both positional and named arguments
      def json_rpc_request(id, method, *, **, &)
        self.class.request(@batch, *json_rpc_id_method(id, method), *, **, &json_rpc_wrap_converter(&))
      end

      # Process the currently batched requests.
      #  @return [nil] if the batch was empty or all the requests were notifications
      #  @return [#value] a transport-specific future/promise (async operations)
      #  @return [Hash<String|Integer, Proc>] map of ids to result proc
      #  @raise  [Error] if the batch is not sent OR if the response has a transport issue
      #  @note the batch is automatically reset if it is successfully delivered to the transport.
      def json_rpc_invoke(&batch_converter)
        batch_converter ||= DEFAULT_BATCH_CONVERTER

        wrapped_converter = proc do |**response_opts, &batch_result|
          # Prefix the incoming response_opts before our userland converter sees them
          prefixed_opts = @options_config.to_user_space(response_opts)
          batch_converter.call(**prefixed_opts, &batch_result)
        end

        # De-prefix the outgoing request options so the transport sees natural options. and exclude converter
        transport_opts = @options_config.to_transport_space(@opts.except(:converter))
        self.class.invoke(@batch, transport_opts, batch_converter: wrapped_converter, &@transport).tap { @batch.clear }
      end

      # Create a single request Endpoint with the same configuration as this Batch
      # @overload json_rpc_endpoint(**with_opts)
      #  @param with_opts [Hash] optional context options to override
      #  @return [Endpoint]
      def json_rpc_endpoint(**)
        Endpoint.new(**@opts, namespace: @namespace, next_id: @next_id, options_config: @options_config, &@transport)
                .with(**)
      end
    end

    class << self
      include ClassHelpers

      # @!method transport(id, request_json, **transport_opts, &transport_response)
      #  @abstract  Signature for the block passed to {.invoke}
      #
      #  When **id** is nil it must return immediately after dispatching the request, without calling
      #  **&{transport_response}**.
      #  Transport errors when dispatching the request should also be allowed to propagate immediately.
      #
      #  Otherwise, in synchronous operations a transport should then...
      #    * block waiting for the JSON-RPC response, raising {TimeoutError} if a response is not received
      #      before the optional **:timeout** expires.
      #    * call the **&{transport_response}** proc with a block that returns the response string or raises
      #      {InvalidResponse}
      #    * return the result of the above call or allow its error to propagate
      #
      #  To support asynchronous operations, when **:async** is set, the transport should immediately return a
      #  future/promise that is eventually resolved from the **&{transport_response}** callback.
      #
      #  @param id [String|Integer|nil] trace id for the request or nil for a notification.
      #  @param transport_opts [Hash] transport options.
      #
      #    Custom transport options should use a descriptive prefix (e.g., `http_`, `mqtt_`).
      #
      #  @option transport_opts :async [Boolean] handle responses asynchronously
      #  @option transport_opts :timeout [Numeric] request timeout
      #  @option transport_opts :converter Reserved for internal use
      #  @yield [**response_opts, &json_response] the &{transport_response}
      #  @return [void] for notifications (when id is nil)
      #  @return [#value] a future/promise if **:async** was requested
      #  @return [Object] the result of the call to &{transport_response}
      #  @raise [InternalError] if something goes wrong with the transport
      #  @raise [TimeoutError] if a synchronous request times out
      #  @raise [Error] error raised from &{transport_response} callback
      #  @example Simple HTTP Transport
      #   def simple_http_transport(id, request_json, timeout: 30, **opts, &transport_response)
      #     return post_async(request_json) unless id  # notifications
      #
      #     response = HTTP.timeout(timeout).post('http://api.example.com/rpc',
      #                                          json: request_json)
      #
      #     transport_response.call do
      #       raise JsonRpcKit::InvalidResponse, "HTTP #{response.status}" unless response.status.success?
      #       response.body.to_s
      #     end
      #   end
      #
      #  @example
      #   def json_rpc_transport(id, request_json, async: false, timeout: nil, **opts, &transport_response)
      #     unless id
      #       return send_async(request_json, **opts)   # if there is no id, just fire and forget
      #     end
      #
      #     future = new_future                         # some transport-specific concurrency primitive
      #
      #     send_async(request_json) do |resp, error|   # a transport-specific async with response/error callback
      #
      #        result = transport_response.call do      # NOTE: &transport_response itself takes a block! that...
      #          raise InvalidResponse, error.message if error  # raises InvalidResponse if something went wrong
      #          resp                                   #  or returns the response string
      #        end
      #        future.fulfill(result)                   # fulfill/resolve the future
      #     rescue StandardError => e
      #        future.reject(e)                         # or reject it
      #     end
      #     return future if async                      # async -> immediately return the future
      #
      #     future.wait(timeout)                        # not async so wait on the future
      #     unless future.fulfilled?
      #       raise JsonRpcKit::TimeoutError            # if timeout without response, raise TimeoutError
      #     end
      #     future.value                                # return the resolved value or raise resolved error
      #   end
      #
      #   def json_rpc_endpoint
      #      JsonRpcKit.endpoint { |*a, **kw, &tp_resp| json_rpc_transport(*a, **kw, &tp_resp) }
      #   end

      # @!method transport_response(**response_opts, &json_response)
      #  Block signature for the &transport_response callback provided to {transport}. Handles parsing and extracting
      #  results from the transport's String response.
      #  @param response_opts [Hash] transport options from the response
      #  @option response_opts :content_type [String] if provided must be 'application/json'
      #  @option response_opts :.* [Object] arbitrary transport specific options for tracing, type conversion etc...
      #
      #    Recommend using a consistent prefix for the transport type.
      #  @param json_response [Proc] (required) a callback providing the JSON-RPC response or error
      #
      #    This proc should raise an error (e.g., InvalidResponse) if something has gone wrong with the
      #    response, or otherwise return the String response received from the transport.
      #    Transport errors are automatically wrapped as InvalidResponse by the endpoint.
      #  @return [Object] the result extracted from the response String
      #  @raise [StandardError] any error raised in response processing, or extracted from the response String

      # @!method converter(**response_opts, &result)
      #  @abstract Signature for block provided to {Batch.request}, {Batch#json_rpc_request} or {Endpoint#invoke}
      #  @param response_opts [Hash] transport options from the response (with 'rpc' prefix)
      #  @yield [] &{result} callback
      #  @return [Object] the converted result
      #  @raise [StandardError] the converted error

      # @!method result
      #  Signature for the &result callback provided to a {converter} and for values held in result of {Batch.invoke}
      #  @return [Object] the result object parsed from the response result
      #  @raise [JsonRpcKit::Error, NoMethodError, ArgumentError, JSON::ParserError] errors raised during response
      #    processing

      # Dispatches a JSON-RPC request to the given transport block
      # @param transport_opts [Hash] transport options (including :converter, :async, :timeout, etc.)
      # @param id [String|Integer|nil] request ID (nil for notification)
      # @param method [String] the JSON-RPC method name
      # @param args [Array] positional arguments
      # @param kwargs [Hash] named arguments
      # @yield [id, request_json, **transport_opts, &transport_response] transport block
      # @return [Object] the result from the response (nil for notifications)
      def invoke(transport_opts, id, method, *args, **kwargs, &transport)
        converter = transport_opts.delete(:converter) || DEFAULT_CONVERTER
        raise ArgumentError, 'Async notifications are not supported' if transport_opts[:async] && !id

        request = to_request(id, method, args, kwargs)

        transport_opts.merge!(content_type: CONTENT_TYPE)
        result = transport.call(id, request.to_json, **transport_opts) do
        |content_type: CONTENT_TYPE, **response_opts, &json_response|
          converter.call(**response_opts) { single_response(content_type:, &json_response) }
        end

        id ? result : nil
      end

      private

      def single_response(content_type:, &json_response)
        response_str = call_response(&json_response)
        response_item = parse_response(response_str, content_type:, batch: false)
        from_response(response_item)
      end
    end

    include InstanceHelpers

    # Create a new endpoint context with merged options
    # @param opts [Hash] additional context options to merge
    # @return [Endpoint] new endpoint with merged context
    # @example Basic context creation
    #   async_endpoint = endpoint.with(async: true, timeout: 30)
    # @example Custom merge strategy
    #   # Create contexts with different transport options
    #   fast_endpoint = endpoint.with(timeout: 5)
    #   slow_endpoint = endpoint.with(timeout: 30)
    #   async_endpoint = endpoint.with(async: true)
    def with(klass: self.class, namespace: @namespace, next_id: @next_id, **opts)
      # raise errors on invalid options, and filter out ignored options
      opts = @options_config.filter_opts(opts)
      return self if klass == self.class && opts.empty?

      merged_opts = @options_config.merge_opts(@opts, opts, filtered: true)

      klass.new(**merged_opts, namespace:, next_id:, options_config: @options_config, &@transport)
    end

    # Create a new endpoint context with a default result converter
    # @param replace [Boolean] if true, replaces existing converter; if false, wraps it
    # @yield [**response_opts, &result] result converter
    # @return [Endpoint] new endpoint with converter
    # @example Replace converter
    #   user_endpoint = endpoint.with_conversion { |**, &result| User.from_json(result.call) }
    # @example Wrap existing converter
    #   validated_endpoint = user_endpoint.with_conversion(replace: false) do |**, &result|
    #     result.call.tap(&:validate!)
    #   end
    # @example Remove converter
    #   raw_endpoint = user_endpoint.with_conversion(replace: true)
    def with_conversion(replace: false, &converter)
      raise ArgumentError, 'Block required with replace: false' unless replace || converter

      with(converter: replace ? converter || DEFAULT_CONVERTER : json_rpc_wrap_converter(&converter))
    end

    # @overload method_missing(method, *args, **kwargs, &converter)
    #   Redirects all method calls to {#json_rpc_invoke}
    #   @param method [Symbol] the RPC method to invoke (Symbol converted with ruby_to_json_rpc)
    #   @param args [Array] positional arguments
    #   @param kwargs [Hash] named arguments
    #   @yield [**response_opts, &result] optional result converter
    #   @return [Object] the result from the response (or the result of a converter block)
    #   @return [#value] a transport-specific future/promise (async operations)
    #   @return [nil] for notifications
    #   @raise [StandardError] the error from the response (or as rescued and re-raised by a converter block)
    def method_missing(method, ...)
      json_rpc_invoke(:next_id, method, ...)
    end

    # Fire and forget notification (ie does not get a response)
    # @overload json_rpc_notify(method, *args, **kwargs)
    #   @param method [Symbol|String] the RPC method to invoke (Symbol converted with ruby_to_json_rpc)
    #   @param args [Array] positional arguments
    #   @param kwargs [Hash] named arguments
    #   @return [nil]
    def json_rpc_notify(method, *, **)
      (@opts[:async] ? with(async: false) : self).json_rpc_invoke(nil, method, *, **)
      nil
    end

    # Execute JSON-RPC method asynchronously
    # @overload json_rpc_async(id, method, *args, **kwargs, &converter)
    #   @param id [String|Integer|Symbol] request ID (:next_id for auto-generated, nil is not valid for explicit async)
    #   @param method [Symbol|String] the RPC method to invoke
    #   @param args [Array] positional arguments
    #   @param kwargs [Hash] named arguments
    #   @yield [**response_opts, &result] optional result converter
    #   @return [#value] a transport-specific future/promise
    def json_rpc_async(id, method, ...)
      (@opts[:async] ? self : with(async: true)).json_rpc_invoke(id, method, ...)
    end

    # Invokes JSON-RPC
    # Invokes a JSON-RPC method with explicit ID control
    # @overload json_rpc_invoke(id, method, *args, **kwargs, &converter)
    #  @param id [String|Integer|Symbol|nil] request ID (:next_id for auto-generated, nil for notification)
    #  @param method [Symbol|String] the RPC method to invoke (Symbol converted with ruby_to_json_rpc)
    #  @param args [Array] positional arguments
    #  @param kwargs [Hash] named arguments
    #  @yield [**response_opts, &result] optional result converter (wraps the {#with_conversion current converter})
    #  @yieldparam response_opts [Hash] transport response options
    #  @yieldparam result [Proc] callback to get the JSON-RPC result or raise its error
    #  @yieldreturn [Object] the converted result
    #  @note As per JSON-RPC spec it is an error to provide both positional and named arguments
    #  @return [Object] the result from the response (or the result of a converter block)
    #  @return [#value] a transport-specific future/promise (async operations)
    #  @return [nil] for notifications
    #  @raise [StandardError] the error from the response (or as rescued and re-raised by a converter block)
    # @example Explicit ID
    #   result = endpoint.json_rpc_invoke({}, 'custom-123', 'get_user', id: 456)
    # @example Auto-generated ID
    #   result = endpoint.json_rpc_invoke({}, :next_id, 'get_user', id: 456)
    # @example Notification (no response)
    #   endpoint.json_rpc_invoke({}, nil, 'log_event', message: 'test')
    # @example With transport options
    #   result = endpoint.json_rpc_invoke({timeout: 30}, :next_id, 'get_user', id: 456)
    def json_rpc_invoke(id, method, *, **, &)
      # We need to do a final wrap of the converter so that it receives properly prefixed response options
      wrapped_converter = proc do |**response_options, &result|
        # prefix the incoming response options before our user land converters see them
        response_options = @options_config.to_user_space(response_options)
        json_rpc_wrap_converter(&).call(**response_options, &result)
      end

      # de prefix the outgoing request options, add wrapped converter
      transport_opts = @options_config.to_transport_space(@opts.merge(converter: wrapped_converter))

      self.class.invoke(transport_opts, *json_rpc_id_method(id, method), *, **, &@transport)
    end

    # Create a batch endpoint from this context
    # @overload json_rpc_batch(**context_opts)
    #   @param context_opts [Hash] additional context options to merge with current context
    #   @return [Batch] batch endpoint with merged context
    #   @example Basic batch creation
    #     batch = endpoint.json_rpc_batch
    #     batch.get_user(id: 1).get_user(id: 2)
    #     results = batch.json_rpc_invoke
    #   @example Batch with context options
    #     batch = endpoint.with(timeout: 60).json_rpc_batch
    #     results = batch.get_user(id: 1).json_rpc_invoke
    def json_rpc_batch(**)
      with(klass: Batch, **)
    end
  end
end
