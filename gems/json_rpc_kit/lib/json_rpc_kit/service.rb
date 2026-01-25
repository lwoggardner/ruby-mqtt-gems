# frozen_string_literal: true

require_relative 'helpers'
require_relative 'transport_options'

module JsonRpcKit
  # This module provides a framework for receiving JSON-RPC requests, resolving them with Ruby methods,
  # and sending responses.
  #
  # It is agnostic to the underlying transport (HTTP, MQTT, WebSocket) and provides a minimal concurrency abstraction
  # for optional asynchronous processing.
  #
  # ## Key Service logic components
  # - {Registry} Class level utilities to map JSON-RPC methods to Ruby methods.
  # - {#json_rpc_call} - Service handler interface mapping JSON-RPC requests to business logic in Ruby.
  # - {#json_rpc_async?} - Policy interface for determining which methods would benefit from asynchronous processing.
  #
  # ## Key Transport logic components
  # - {Service.transport} - Create a transport handler
  # - {Transport#json_rpc_transport} - The transport handler interface to dispatch incoming requests and send back
  #   responses.
  #
  # ## Quick Start
  #
  # ### 1. Define a Service
  # Include this module in your class and define JSON-RPC mappings to methods
  # ```ruby
  # class UserService
  #   include JsonRpcKit::Service
  #
  #   json_rpc_namespace 'users', async: true
  #
  #   json_rpc :get_user
  #   def get_user(id)
  #     { id: id, name: "User #{id}" }
  #   end
  #
  #   json_rpc :list_users
  #   def list_users(limit: 10)
  #     (1..limit).map { |i| { id: i, name: "User #{i}" } }
  #   end
  # end
  # ```
  #
  # ### 2. Create Transport Handler
  # Use {.transport} to define a handler to process JSON-RPC requests
  #
  # ```ruby
  # service = UserService.new
  # handler = JsonRpcKit::Service.transport(service: service, merge: nil)
  # ```
  #
  # ### 3. Handle Requests
  # Call the handler with a JSON-RPC request and obtain a JSON-RPC response
  # ```ruby
  # # Synchronous (HTTP)
  # response_json, opts = handler.call(request_json, request_opts)
  #
  # # Asynchronous (MQTT, WebSocket)
  # handler.call(request_json, request_opts) do |response_json, opts|
  #   send_response(response_json, opts)
  # end
  # ```
  #
  module Service
    # Registry methods added to the class that includes {Service}
    # @example
    #   json_rpc :create_user, async: true  # => 'createUser' (async: true)
    #   json_rpc_namespace 'users', async: true
    #   json_rpc :get_user                  # => "users.getUser" (async: true)
    #   json_rpc :list_users                # => "users.listUsers" (async: true)
    #
    #   json_rpc_namespace 'system', async: false
    #   json_rpc :ping                      # => "system.ping" (async: false)
    #
    #   json_rpc_namespace nil, async: false
    #   json_rpc :ping                      # => "ping", async: false
    #   json_rpc_namespace 'users', async: nil
    #   json_rpc :get_user                  # !> Error 'no default async for namespace: 'users'
    module Registry
      include Helpers

      # Simple method registry
      # @return [Hash<String,Symbol>] map of json-rpc method names to ruby method names, as registered via {#json_rpc}
      attr_reader :json_rpc_methods

      # @return [Set] list of json-rpc method names that would benefit from parallel execution during batch operations
      attr_reader :json_rpc_async_methods

      # @!visibility private
      def json_rpc_async
        @json_rpc_async ||= {}
      end

      # Register a method for JSON-RPC dispatch
      #
      # @overload json_rpc(method, namespace: json_rpc_namespace:, async: json_rpc_async[namespace])
      #  Converts ruby method name to JSON_RPC (camelCase) with optional namespace
      #
      #  In this form the default async will come from that stored in either the supplied or inherited namespace,
      #  or in the nil namespace.
      #
      #  @param namespace [String] a namespace prefix for the method.  Defaults from the most recent call to
      #   {json_rpc_namespace}
      # @overload json_rpc(method, as:, async: async: json_rpc_async[nil])
      #  Use an explicit JSON-RPC method name.
      #
      #  In this form the default async comes from that stored in the nil namespace
      #  @param as [String] a fully qualified JSON-RPC method name
      # @param method [Symbol] the ruby method name (snake_case)
      # @param async [Boolean] whether this method would benefit from asynchronous execution
      #   * `true` - method can be executed asynchronously (e.g., slow, IO-blocking operations)
      #   * `false` - method should be executed synchronously (e.g., fast, non-blocking operations)
      #   * Must be provided explicitly or inherited from a default stored via {json_rpc_namespace}
      # @return [String] the registered JSON-RPC method name
      def json_rpc(method, as: nil, namespace: as ? nil : json_rpc_namespace, async: :default)
        as ||= ruby_to_json_rpc(method, namespace: namespace)

        raise ArgumentError, 'async: must be explicitly true or false' unless [true, false, :default].include?(async)

        if async == :default
          async = json_rpc_async.fetch(namespace, json_rpc_async[nil])
          raise ArgumentError, "no async for namespace:#{namespace || 'nil'}" unless [true, false].include?(async)
        end

        @json_rpc_methods ||= {}
        @json_rpc_methods[as] = method

        @json_rpc_async_methods ||= Set.new
        @json_rpc_async_methods << as if async
        as
      end

      # Set or get the default namespace for subsequent {json_rpc} declarations
      #
      # @overload json_rpc_namespace()
      #   Get the current namespace
      #   @return [String, nil] current namespace
      #
      # @overload json_rpc_namespace(namespace, async:)
      #   Set the namespace and its async default for subsequent {json_rpc} declarations
      #   @param namespace [String] namespace prefix for methods
      #   @param async [Boolean|nil] whether methods in this namespace would benefit from async execution,
      #     or nil to remove the default
      #   @return [String] the namespace
      #
      def json_rpc_namespace(*namespace, async: nil)
        if namespace.any?
          @json_rpc_namespace = namespace.first

          raise ArgumentError, 'async: must be true, false or nil' unless async.nil? || [true, false].include?(async)

          if async.nil?
            json_rpc_async.delete(@json_rpc_namespace)
          else
            json_rpc_async[@json_rpc_namespace] = async
          end
        end
        @json_rpc_namespace
      end
    end

    # @!parse
    #  # @abstract Documents the task spawning interface
    #  class Task
    #    class << self
    #       # Called based on the type of transport (see {#json_rpc_transport})
    #       #
    #       # - For **synchronous transports**: Only called for inner {Transport#async_policy_proc async-hinted}
    #       #    request tasks within batches
    #       # - For **asynchronous transports**: Called for single async-hinted requests or for batches with containing
    #       #    async-hinted requests (async_count: > 0) and for those async-hinted item requests
    #       #
    #       # @yield &task to execute asynchronously
    #       # @yieldreturn [Object] Result of the task
    #       # @return [#value] Object that blocks until complete and returns result
    #       def async(&task)
    #       end
    #
    #       # Called regardless of transport type or async hints.
    #       # Spawner can choose to spawn a task asynchronously or return nil for synchronous execution.
    #       #
    #       # @param task_type [Symbol] `:batch` or `:request`
    #       # @param request_opts [Hash] Mutable transport-specific options (e.g., for passing barriers between tasks)
    #       # @param context [Hash] Immutable request metadata
    #       # @option context [Integer] :count `:batch` Total items in the batch
    #       # @option context [Integer] :async_count `:batch` Number of items where async would be beneficial
    #       # @option context [Boolean] :async `:request` Whether async execution would be beneficial for this method
    #       # @option context [Boolean] :batch `:request` Whether this is a batch item (vs single request)
    #       # @option context [String, Integer, nil] :id `:request` JSON-RPC request id
    #       # @option context [String] :method `:request` JSON-RPC method name
    #       # @yield Task to execute
    #       # @return [#value] Object that blocks until complete and returns result
    #       # @return [nil] For synchronous execution (block executed immediately)
    #       # @example MQTT Spawner with Barrier (Full Control Interface)
    #       #  spawner = proc do |task_type, request_opts, **context, &block|
    #       #    watcher = request_opts[:timeout_watcher]
    #       #    next nil unless watcher  # Synchronous if no watcher
    #       #
    #       #    case task_type
    #       #    when :batch
    #       #      next nil unless context[:async_count].positive?
    #       #
    #       #      # Add a Barrier to request_opts so it is available to spawn the request tasks
    #       #      request_opts[:barrier] = watcher.new_barrier
    #       #
    #       #      # Wrap block with an ensure barrier.stop, so that all our async requests are timed out
    #       #      # if this task is timed out.
    #       #      watcher.with_timeout(timeout) { request_opts[:barrier].wait!(&block) }
    #       #
    #       #    when :request
    #       #      next nil unless context[:async]
    #       #      request_opts[:barrier].async(&block)
    #       #    end
    #       #  end
    #       def call(task_type, request_opts, **context, &task)
    #       end
    #     end
    #
    #     # Returns the result of the task block or raises its error
    #     #
    #     # @return [Object]
    #     # @raise  [StandardError]
    #     def value()
    #     end
    #  end

    SyncTask = Data.define(:result, :error)

    # Implements the **Simple** TaskSpawner interface, but just runs tasks directly
    class SyncTask < Data
      # @!attribute [r] error
      #  @return [StandardError]

      # yields the block
      def self.async
        new(result: yield, error: nil)
      rescue StandardError => e
        new(result: nil, error: e)
      end

      # returns the value, or raises the error
      def value
        raise error if error

        result
      end
    end

    # Encapsulates JSON-RPC transport configuration
    #
    # Created via {Service.transport}, this class holds the configuration for
    #   * manipulating transport request and response options
    #   * managing when and how asynchronous tasks are spawned
    #   * invoking a {Service#json_rpc_call} handler
    #
    # ## Task spawning interface
    #
    # Parallel execution can improve throughput when processing batch requests containing
    # multiple independent operations, or when individual methods perform I/O or blocking operations.
    #
    # For naturally asynchronous transports (e.g., MQTT, message queues) that process requests
    # on dedicated threads, spawning tasks prevents blocking the transport's message handling.
    #
    # The `async:` parameter to {Service.transport} accepts objects implementing either:
    # - {Task.async #async} - Simple Interface that fully respects async hints
    # - {Task.call #call} - Full Control Interface for custom spawning logic
    #
    # Async hints come from {Service#json_rpc_async?} metadata, indicating which methods
    # would benefit from parallel execution. See {#async_policy_proc} for the hint provider.
    #
    # ### Task Nesting
    #
    # Batch Request - requests nested inside batch, can pass information from batch to request via opts
    # ```
    #   :batch,opts={},  (context: { count: 3, async_count: 2 }) # opts[:x] = 'y')
    #     └─> :request,{x: 'y'} (context: { async: true, batch: true, id: "xx-1", method: "foo" })
    #     └─> :request,{x:,'y'} (context: { async: true, batch: true, id: "yy-32", method: "bar" })
    #     └─> :request,{x:,'y'} (context: { async: false, batch: true, id: "zz-43", method: "baz" })
    # ```
    # Single Request - no nesting:
    # ```
    #   :request, opts={} (context: { async: true, batch: false, id: 1234, method: "foo" })
    # ```
    #
    # ### Task Interface
    #
    # Objects returned by spawners must implement:
    #
    # ```ruby
    #   task.value # => block until complete and then return the task result or raise its error
    # ```
    class Transport
      class << self
        # @!visibility private
        def service_proc(service:, &service_proc)
          return service_proc if service_proc

          if service.respond_to?(:json_rpc_call)
            service.method(:json_rpc_call).to_proc
          elsif service.respond_to?(:to_proc)
            service.to_proc
          elsif service.respond_to?(:call)
            ->(*a, **kw) { service.call(*a, **kw) }
          else
            raise ArgumentError, 'No valid service: or block provided'
          end.tap { it.call({}, {}, nil, 'rpc.validate') }
        end

        # @!visibility private
        def async_policy_proc(service:, async_policy: :not_set)
          if async_policy == :not_set
            if service.respond_to?(:json_rpc_async?)
              service.method(:json_rpc_async?).to_proc
            else
              ->(*, **) { false }
            end
          elsif async_policy.nil? || [true, false].include?(async_policy)
            ->(*, **) { async_policy ? true : false }
          elsif async_policy.respond_to?(:to_proc)
            async_policy.to_proc
          elsif async_policy.respond_to?(:call)
            ->(*a, **kw) { async_policy.call(*a, **kw) }
          else
            raise ArgumentError, "Invalid async_policy: #{async_policy.class.name}"
          end.tap { it.call({}, id: 'validation', method: 'rpc.validate') }
        end

        # @!visibility private
        def async(async:)
          return SyncTask unless async

          async = async.to_proc if async.respond_to?(:to_proc) && !async.respond_to?(:call)
          async.tap { validate_async!(async:) }
        end

        def validate_async!(async:)
          if async.respond_to?(:call)
            async.call(:request, {}, id: nil, method: 'rpc.validate', async: false, batch: false) { :validate }&.value
            async.call(:batch, {}, async_count: 0, count: 0) do
              async.call(:request, {}, id: nil, method: 'rpc.validate', async: false, batch: false) do
                :validate
              end&.value
            end&.value
          elsif async.respond_to?(:async)
            async.async { :validate }.value
          else
            raise ArgumentError, "async:(#{async.class.name}): must implement #call or #async"
          end
        end
      end

      # @return [Proc<{#json_rpc_call}>] Proc used to invoke the {Service} with a request
      attr_reader :service_proc

      # Provides hints for which requests could benefit from asynchronous processing.
      # Defaults to the service's {JsonRpcKit::Service#json_rpc_async? json_rpc_async?} method if `:async_policy` is
      # not explicitly provided.
      # @return [Proc] Proc<{JsonRpcKit::Service#json_rpc_async? json_rpc_async?}>
      attr_reader :async_policy_proc

      # @!visibility private
      def initialize(
        async: nil, async_policy: :not_set,
        service: nil, **transport_opts, &service_proc
      )
        @service_proc = Transport.service_proc(service:, &service_proc)
        @async = Transport.async(async:)
        @async_policy_proc = Transport.async_policy_proc(service:, async_policy:)
        @options_config = TransportOptions.create_from_opts(transport_opts)

        raise ArgumentError, "Unknown options #{transport_opts.keys}" unless transport_opts.empty?
      end

      # Transport options configuration
      #
      # Handles prefix, filter, and merge for request/response options:
      # - Request options received from transport are prefixed before passing to service
      # - Response options from service are de-prefixed, filtered, and merged before returning to transport
      #
      # @return [TransportOptions]
      attr_reader :options_config

      # rubocop:disable Style/OptionalBooleanParameter

      # The task spawning proc derived from the `:async` parameter to {.transport}
      # @!attribute [r] async_proc
      # @return [Proc<Task.async>] Simple Interface task spawner (if `async:` parameter implements `#async`)
      # @return [Proc<Task.call>] Full Control Interface task spawner (if `async:` parameter implements `#call`)
      def async_proc(async_transport = false)
        # Strictly a transport could sometimes send a callback and sometimes not. Highly unlikely
        @async_procs ||= {}
        @async_procs[async_transport] ||=
          if @async.respond_to?(:call)
            ->(*request_info, **context, &block) { @async.call(*request_info, **context, &block) }
          elsif @async.respond_to?(:async)
            ->(*, **context, &block) { @async.async(&block) if simple_async?(async_transport, **context) }
          end
      end
      # rubocop:enable Style/OptionalBooleanParameter

      # @!visibility private
      def simple_async?(async_transport, async: nil, async_count: 0, batch: false, **)
        # If transport is asynchronous, respect the hint - outer request is single async, or batch has async requests
        # If transport is synchronous, only do batch requests that are hinted as async
        async_transport ? (async || async_count.positive?) : (async && batch)
      end

      # Transport handler interface for incoming JSON-RPC requests.
      #
      # This is the signature of the Proc returned to {Service.transport}
      #
      # **Transport type:**
      #
      # The presence of `&transport_callback` distinguishes transport types:
      # - **Synchronous transports** (HTTP, stdio): No callback - handler blocks and returns result
      # - **Asynchronous transports** (MQTT, message queues): Callback provided - handler returns immediately
      #
      # Asynchronous transports typically process requests on dedicated message threads and use
      # the callback and asynchronous tasks to avoid blocking.
      #
      # This impacts the behaviour of the {Task.async Simple} TaskSpawner interface in terms of which tasks are
      # processed asynchronously.
      #
      # Note that a {Task.call Full Control} TaskSpawner is called regardless of the transport type and can choose to
      # block or not as necessary.
      #
      # @param request_json [String] JSON-RPC request (single or batch)
      # @param request_opts [Hash] Transport metadata (will be prefixed if configured)
      # @yield [response_json, response_opts] optional &callback for async transports
      # @yieldparam response_json [String|nil] JSON-RPC response (nil if all notifications)
      # @yieldparam response_opts [Hash] Filtered and merged response options
      # @return [#value] **asynchronous** transport
      # @return [[String|nil, Hash]] `[response_json, response_opts]` **synchronous** transport (no &callback given)
      def json_rpc_transport(request_json, request_opts = {}, &)
        Request.new(request_json, request_opts, transport: self).execute(&)
      end

      # Returns the transport handler as a proc.
      #
      # @return [Proc] Handler proc wrapping {#json_rpc_transport}
      def to_proc
        method(:json_rpc_transport).to_proc
      end

      def reduce_response_options(*response_options_list)
        options_config.reduce_to_transport_space(*response_options_list)
      end
    end

    # @!visibility private
    class Request
      # @!visibility private
      class << self
        include Helpers

        # Parse the JSON and tag/augment/enrich
        def parse_with_async_policy(request_json, request_opts, &async_policy)
          request = parse_request(request_json, **request_opts.slice(:content_type))

          batch = request.is_a?(Array)
          async_count = (batch ? request : [request]).count do |r|
            async_policy.call(request_opts, **r.slice(:id, :method)).tap do |async|
              r.merge!(async: async ? true : false, batch:)
            end
          end

          [batch, request, async_count]
        end
      end

      # @!visibility private
      attr_reader :request_opts, :frozen_request_opts, :async_count, :request, :transport, :parse_error

      # @!visibility private
      def initialize(request_json, request_opts, transport:)
        @transport = transport
        # The transport space request opts are available to the async proc
        @request_opts = request_opts
        # Frozen, user space request opts are available to the async_policy: and service: handler
        @frozen_request_opts = transport.options_config.to_user_space(request_opts).freeze

        @batch, @request, @async_count =
          Request.parse_with_async_policy(request_json, @frozen_request_opts, &transport.async_policy_proc)
      rescue StandardError => e
        @parse_error = Error.rescue_error(nil, e)
      end

      # Process the request - block is the transport_callback
      def execute(&)
        task =
          if parse_error
            parse_error_task(&)
          elsif batch?
            batch_task(&)
          else
            single_request_task(&)
          end

        block_given? ? task : task.value
      end

      private

      def batch?
        @batch
      end

      def parse_error_task(&)
        SyncTask.async { respond(parse_error.to_json, &) }
      end

      def batch_task(&)
        async_call(:batch, block_given?, count: request.size, async_count:) do
          respond(*handle_batch(*request, &transport.service_proc), &)
        end
      end

      def single_request_task(&)
        async_call(:request, block_given?, **request.slice(:async, :batch, :id, :method)) do
          respond(*handle_request(**request, &transport.service_proc), &)
        end
      end

      def async_call(request_type, async_transport = nil, **context, &)
        transport.async_proc(async_transport)&.call(request_type, request_opts, **context, &) || SyncTask.async(&)
      end

      def handle_batch(*requests, &)
        tasks = requests.map do |r|
          # Inner async call
          async_call(:request, **r.slice(:batch, :async, :id, :method)) do
            handle_request(**r, &) # NOTE: batch: true is embedded in r by .parse
          end
        end.map(&:value).select(&:first) # Filter out notifications
        return nil if tasks.empty?

        result_list, response_opts_list = tasks.transpose
        [result_list.to_json, *response_opts_list]
      rescue StandardError => e
        # expect this is json generation error (since handle_request rescues errors)
        # some non JSONable object in the results
        [Error.rescue_error(nil, e).to_json, *response_opts_list]
      end

      def handle_request(batch:, id: nil, method: nil, params: [], **_, &service)
        args, kwargs = params.is_a?(Array) ? [params, {}] : [[], params]
        result = service.call(frozen_request_opts, response_opts = {}, id, method, *args, **kwargs)
        rpc_result = id ? { jsonrpc: '2.0', id: id, result: result } : nil
        return [nil, response_opts] unless rpc_result

        batch ? [rpc_result, response_opts] : [rpc_result.to_json, response_opts]
      rescue StandardError => e
        rpc_error = Error.rescue_error(id, e)
        batch ? [rpc_error, response_opts] : [rpc_error.to_json, response_opts]
      end

      def respond(response_json, *response_opts_list, &callback)
        return callback&.call(nil, {}) unless response_json

        # TODO: Somehow here we need to log bad response options, but we don't have a logging facility
        response = [response_json, transport.reduce_response_options(*response_opts_list)]
        callback&.call(*response) || response
      end
    end

    class << self
      include Helpers

      # Configures a {Transport} and wraps it in a handler proc for processing incoming JSON-RPC requests
      #
      # This is the entry point for creating JSON-RPC service handlers that work with
      # various transports (HTTP, MQTT, WebSocket) and concurrency models (Threads, Fibers, Async gem).
      #
      # @overload transport(service:,async: nil, async_policy: nil, **transport_opts)
      #   @param service [#json_rpc_call] Service implementation
      #   @param async [#call, #async, nil] see {Transport#async_proc Transport#async_proc}
      #   @param async_policy [Boolean, #call, nil] see {Transport#async_policy_proc Transport#async_policy_proc}
      #   @param transport_opts [Hash] configure {TransportOptions}
      #   @option transport_opts :prefix,:merge,:filter,:ignore [Object] see {TransportOptions}
      #
      # @overload transport(service, async: nil, async_policy: nil,**transport_opts)
      #   Positional service argument (sugar for service: keyword)
      #
      # @overload transport(async: nil, async_policy: nil, **transports_opts, &service_proc)
      #   Service handler as a block argument
      #   @yield [request_opts, response_opts, id, method, *args, **kwargs] Service handler (see {#json_rpc_call})
      #
      # @return [Proc] request handler Proc<{Transport#json_rpc_transport}>
      #
      # @example HTTP/Rack Transport (synchronous)
      #   handler = JsonRpcKit::Service.transport(
      #     prefix: 'http',
      #     filter: %i[status headers],
      #     merge: proc { |k, old, new|
      #       case k
      #       when :status then [old, new].max
      #       when :headers then old.merge(new)
      #       end
      #     }
      #   ) do |request_opts, response_opts, id, method, *args, **kwargs|
      #     # Handle request
      #   end
      #
      #   # In Rack app
      #   def call(env)
      #     request_opts = { headers: extract_headers(env) }
      #     response_json, opts = handler.call(env['rack.input'].read, request_opts)
      #     [opts[:status] || 200, {'Content-Type' => 'application/json'}.merge(opts[:headers]), [response_json]]
      #   end
      def transport(service_arg = nil, service: service_arg, **transport_opts, &service_proc)
        Transport.new(service:, **transport_opts, &service_proc).to_proc
      end

      def included(base)
        base.extend(Registry)
        base.json_rpc :list_methods, namespace: 'system', async: false
      end
    end

    # Simple discovery of available method names, automatically bound as `system.listMethods`
    def list_methods
      self.class.json_rpc_methods&.keys
    end

    # Get a transport handler proc for this service.
    #
    # Convenience method that calls {Service.transport} with this service instance.
    #
    # @param transport [Hash] Transport options (see {Service.transport})
    # @return [Proc] Handler proc (see {Transport#to_proc})
    def json_rpc_transport(**transport)
      Service.transport(**transport, service: self)
    end

    # Determine if async execution would be beneficial for a JSON-RPC method.
    #
    # This method provides the AsyncPolicy interface. It's called to determine whethertransport
    # spawning an async task for a method would be beneficial (e.g., for I/O-bound operations,
    # slow computations, or methods that yield control).
    #
    # Override this method to provide custom, per-request logic based on authentication,
    # rate limits, or other request context.
    #
    # The default implementation uses the async metadata from {Registry.json_rpc} declarations.
    #
    # @overload json_rpc_async?(request_opts, id, method)
    #  @param request_opts [Hash] Frozen, prefixed transport metadata from the request
    #  @param id [String, Integer, nil] JSON-RPC request id
    #  @param method [String] JSON-RPC method name
    #  @return [Boolean] true if async execution would be beneficial for this method
    #
    #  @example Custom async logic
    #   def json_rpc_async?(request_opts, id, method)
    #     # Only async for premium users
    #     return false unless request_opts[:user_tier] == :premium
    #     super
    #   end
    def json_rpc_async?(_request_opts, _id, method)
      self.class.json_rpc_async_methods&.include?(method)
    end

    # Handle a JSON-RPC request.
    #
    # This is called by the transport handler for each request. The default implementation:
    #   1. Finds the ruby method associated with the JSON-RPC method (from {Registry.json_rpc_methods})
    #   2. Passes request_opts to {#json_rpc_route} to determine which object should receive the call
    #   3. Passes the args/kwargs to the ruby method on the receiver
    #
    # @note Custom implementations should validate method calls (e.g., to avoid exposing `instance_eval`)
    #
    # rubocop:disable Metrics/ParameterLists

    # @param request_opts [Hash] Frozen, prefixed transport metadata from the request
    # @param response_opts [Hash] Mutable hash for populating response options (e.g., HTTP status, headers)
    # @param id [String, Integer, nil] JSON-RPC request id (nil for notifications)
    # @param method [String] JSON-RPC method name
    # @param args [Array] Positional parameters from the JSON-RPC request
    # @param kwargs [Hash] Named parameters from the JSON-RPC request
    # @return [Object] JSON-serializable result
    # @raise [Error, StandardError] Error to be encapsulated in JSON-RPC error response
    def json_rpc_call(request_opts, response_opts, id, method, *args, **kwargs)
      return true if method == 'rpc.validate'

      rb_method = self.class.json_rpc_methods[method]
      service = json_rpc_route(request_opts, response_opts, method, args, kwargs, via: rb_method) if rb_method
      raise NoMethodError, "No RPC service for #{method}" unless service&.respond_to?(method) # rubocop:disable Lint/RedundantSafeNavigation

      service.public_send(method, *args, **kwargs)
    rescue StandardError => e
      json_rpc_error(request_opts, id, method, e) if respond_to?(:json_rpc_error)
      raise
    end
    # rubocop:enable Metrics/ParameterLists

    # @!method json_rpc_error(request_opts, id, json_method, error)
    #  @abstract define to log or transform errors
    #  @param [Hash] request_opts (frozen)
    #  @param [String|Integer|nil] id
    #  @param [String] json_method
    #  @param [StandardError] error
    #  @return [void]

    # Routes the JSON-RPC method to a ruby object.
    # @abstract Override this method to route to another object, based on namespace, or options
    #   provided by the transport (MQTT topic, HTTP headers...).
    #
    # Default implementation routes to self.
    #
    # Positional and named arguments can also be mutated here, eg to convert simple Hash to Data/Struct
    #
    # @overload json_rpc_route(request_opts, response_opts, method, args, kwargs, via:)
    #  @param request_opts [Hash<Symbol>] (frozen) options from the transport that received the request
    #  @param response_opts [Hash<Symbol>] (mutable) options for the transport response
    #  @param method [String] method name as received in the JSON-RPC request
    #  @param args [Array] positional arguments (mutable)
    #  @param kwargs [Hash] json object argument (mutable)
    #  @param via [Symbol] the ruby method name as registered with {.json_rpc}
    #  @return [Object] receiver for the method call
    #  @return [nil] to ignore the request (will raise a JSON-RPC NoMethodError to the caller)
    def json_rpc_route(*, via: nil)
      defined?(super) ? super : self
    end
  end
end
