# frozen_string_literal: true

require_relative 'helpers'

module JsonRpcKit
  # Module to act as a receiver or registry/router for JSON-RPC requests.
  # @example
  #  class UserService
  #    include JsonRpcKit::Service
  #
  #    # Set current default namespace
  #    json_rpc_namespace 'users'
  #
  #    # Explicitly bind methods to JSON-RPC method names
  #    json_rpc :get_user # => "users.getUser"
  #    def get_user(id)
  #      # Your implementation
  #      { id: id, name: "User #{id}" }
  #    end
  #
  #    json_rpc :list_users # => "users.listUsers"
  #    def list_users(limit: 10)
  #      # Your implementation
  #      (1..limit).map { |i| { id: i, name: "User #{i}" } }
  #    end
  #  end
  #
  # # Handle JSON-RPC request
  # service = UserService.new
  #
  # request_json, content_type = # Whatever your transport layer is to receive JSON-RPC request string
  # response_json = service.json_rpc_serve(request_json, content_type:)
  module Service
    # Registry methods added to the class that includes {Service}
    module ClassMethods
      # Simple method registry
      # @return [Hash<String,Symbol>] map of json-rpc method names to ruby method names, as registered via {#json_rpc}
      attr_reader :json_rpc_methods

      # Register a method
      # @param method [Symbol] the ruby method (snake_case)
      # @param namespace [String] a namespace prefix for the method
      # @param as [String,nil] the json_rpc method (<namespace>.camelCase). Generated automatically if no provided.
      # @return [String] the registered JSON-RPC method name
      def json_rpc(method, namespace: json_rpc_namespace, as: nil)
        as = "#{namespace}.#{as}" if namespace && as && !as.start_with?(namespace)
        as ||= ruby_to_json_rpc(method, namespace: namespace)
        @json_rpc_methods ||= {}
        @json_rpc_methods[as] = method
        as
      end

      # Set the default name space for next call to {#json_rpc}
      def json_rpc_namespace(*namespace)
        @json_rpc_namespace = namespace.first if namespace.any?
        @json_rpc_namespace
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
      base.json_rpc :list_methods, namespace: 'system'
    end

    class << self
      include Helpers

      # Serve a JSON-RPC request
      #
      # The request is parsed and validated for JSON-RPC request format and content type 'application/json'
      #
      # The receiver is either something that quacks like a {Service} via {#json_rpc_call}, or a block with the same
      # signature. It is invoked with the requested JSON-RPC method and parameters either as position arguments (from
      # JSON list/Array) or keyword arguments (from JSON object/Hash).
      #
      # The receiver is responsible for all input validation.
      #
      # The receiver call returns a ruby object that supports JSON serialisation (#to_json) which is then
      # embedded in the JSON-RPC response.
      #
      # Exceptions raised by the receiver are converted to a JSON-RPC error response.
      #
      # @param request_json [String] the JSON-RPC request string
      # @param receiver [Service, #json_rpc_call] the object to receive the JSON-RPC request.
      # @param content_type [String] if supplied, must be `application/json`
      # @param options [Hash] transport specific options. These are transformed to add 'rpc_' prefix and passed
      #   to the receiver with the keyword arguments.
      # @yield [method, *args, **kwargs] block can be used in lieu of an explicit {#json_rpc_call} receiver.
      # @return [String] a JSON-RPC response containing the result of the call to the receiver or the error that
      #  it raised.
      def serve(request_json, receiver = nil, content_type: JsonRpcKit::CONTENT_TYPE, **options, &)
        parsed = parse(request_json, content_type:, error_class: InvalidRequest)
        version, method, params, id = parsed.values_at(:jsonrpc, :method, :params, :id)
        validate_request!(version, method, params)

        params ||= []
        args, kwargs = params.is_a?(Array) ? [params, {}] : [[], params]
        options.transform_keys! { |k| k.start_with?('rpc_') ? k : :"rpc_#{k}" }

        result = json_rpc_send(receiver, method, *args, **kwargs, **options, &)

        { jsonrpc: '2.0', id: id, result: result }.compact.to_json
      rescue StandardError => e
        Error.rescue_error(id, e)
      end

      private

      def validate_request!(version, method, params)
        raise InvalidRequest, 'Not a JSON-RPC request' unless version
        raise InvalidRequest, 'Invalid method' unless method.is_a?(String)
        raise InvalidRequest, 'Invalid params' unless params.nil? || params.is_a?(Hash) || params.is_a?(Array)
      end

      def json_rpc_send(receiver, method, *, **, &blk_receiver)
        return receiver.json_rpc_call(method, *, **) if receiver.respond_to?(:json_rpc_call)
        return blk_receiver.call(method, *, **) if block_given?

        raise InternalError, "No receiver for #{method}", data: { receiver: receiver.class.name }
      end
    end

    # Simple discovery of available method names, automatically bound as `system.listMethods`
    def list_methods
      self.class.json_rpc_methods&.keys
    end

    # Serve this object via some transport that can receive JSON-RPC requests.
    # @return [String] a JSON-RPC response
    # @see Service.serve
    def json_rpc_serve(json_request, **rpc_options)
      Service.serve(json_request, self, **rpc_options)
    end

    # Interface for {.serve} to receive a JSON-RPC request
    #
    # This implementation
    #   1. finds the ruby method associated with the JSON-RPC method (from {ClassMethods.json_rpc_methods})
    #   2. extracts `rpc_` prefixed args from kwargs, sending them to #{json_rpc_route}
    #   to determine which object should receive the call.
    #   3. passes the args/kwargs to the ruby method on the receiver
    #
    # @param json_method [String] the JSON-RPC method name
    # @param args [Array] positional arguments
    # @param kwargs [Hash] named arguments from the request and transport provided arguments (prefixed with `rpc_`)
    # @return [#to_json] a JSONable result object
    # @raise [Error, StandardError] an error that will be encapsulated in the response.
    # @note Custom implementations should take care to validate method calls (eg to avoid a exposing remote call to
    #   `instance_eval`)
    def json_rpc_call(json_method, *args, **kwargs)
      rpc_info = extract_rpc_options(kwargs)

      method = self.class.json_rpc_methods[json_method]
      service = json_rpc_route(json_method, args, kwargs, rpc_method: method, **rpc_info) if method
      raise NoMethodError, "No RPC service for #{method}" unless service&.respond_to?(method) # rubocop:disable Lint/RedundantSafeNavigation

      service.public_send(method, *args, **kwargs)
    end

    # Routes the json_method to a ruby object.
    # @abstract Override this method to route to another object, based on namespace, or options
    #   provided by the transport (MQTT topic, HTTP headers...). Default implementation routes to self.
    #
    # Positional and named arguments can also be mutated here, eg to convert simple Hash to Data/Struct
    #
    # @param json_method [String] method name as received from JSON-RPC transport
    # @param args [Array] positional arguments (mutable)
    # @param kwargs [Hash] json object argument (mutable)
    # @param rpc_info [Hash] properties from the transport (without rpc_prefix)
    # @option rpc_info [Symbol] :rpc_method the ruby method that the result object will receive
    #   as registered with {ClassMethods.json_rpc}
    # @return [Object] receiver for the method call
    # @return [nil] to ignore the request (will raise a JSON-RPC NoMethodError to the caller)
    def json_rpc_route(json_method, args, kwargs, **rpc_info)
      defined?(super) ? super : self
    end
  end
end
