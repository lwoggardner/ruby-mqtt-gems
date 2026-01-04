# frozen_string_literal: true

module JsonRpcKit
  # An endpoint for dispatching JSON-RPC requests via ruby calls.
  #
  # Requests can be sent via
  # * the static method {.invoke} (also {JsonRpcKit.invoke})
  # * the instance method {#json_rpc_invoke}
  # * any plain method on an instance (via {#method_missing} )
  #
  # This class covers the JSON-RPC generation of correlation ids and encoding/decoding of method and parameters.
  # It delegates the actual send/receive to a {.transport} proc.
  class Endpoint
    include Helpers

    class << self
      include Helpers

      # @macro [new] invoke_params
      #  @param args [Array] positional arguments
      #  @param kwargs [Hash] named arguments.  Arguments prefixed with `rpc_` are extracted and sent to the
      #    {.transport} block as request options (without the prefix).
      #  @option kwargs [Boolean] :rpc_notify use for fire and forget notifications
      #  @option kwargs [Boolean] :rpc_async convention to have the transport immediately return a Future/Promise
      #  @option kwargs [Numeric] :rpc_timeout convention to support a timeout for the request
      #  @note As per JSON-RPC spec it is an error to provide both positional arguments and (non `rpc_`)
      #    named arguments.
      #  @return [void] if `rpc_notify` is set
      #  @return [#value] a transport-specific future/promise if `rpc_async` is set (and supported)
      #  @return [Object] the result from the response (or the result of a &{.converter} block)
      #  @raise  [StandardError] the error from the response (or as rescued and re-raised by a &{.converter} block)

      # @!method transport(id, request_json, **request_opts, &response)
      #  @abstract  Signature for the block to {.invoke}
      #  @param id [String|Integer] correlation id for the request, this will be nil for a notification.
      #  @param request_json [String]
      #  @param request_opts [Hash] options prefixed with `rpc_` from the request call, stripped of that prefix.
      #  @option request_opts :async [Boolean] whether to return a future/promise for async requests
      #  @option request_opts :timeout [Numeric] timeout for the request
      #  @yield [response_json, **response_opts, &converter) the &{response} callback
      #  @return [Object] the result of &response, or a future/promise if the :async option was set.
      #  @raise [JsonRpcKit::InternalError] if something goes wrong with the transport
      #  @raise [JsonRpcKit::TimeoutError] if a synchronous request times out
      #  @raise [StandardError] error raised from &{response} callback

      # @!method response(response_json, **response_opts, &converter)
      #  Block signature for the &response callback provided to {transport}
      #  @param response_json [String]
      #  @param response_opts [Hash] transport options from the response (without 'rpc' prefix)
      #  @yield |**response_opts, &result| optional &{converter} for the response result or to rescue its error.
      #  @return [Object] the result from the response, or result of {converter}
      #  @raise [StandardError] the embedded error from the response (or as rescued and re-raised by {converter})

      # @!method converter(**response_opts, &result)
      #  @abstract Signature for block provided to {response}
      #  @param response_opts [Hash] transport options from the response (with 'rpc' prefix)
      #  @yield [] &{result} callback
      #  @return [Object] the converted result
      #  @raise [StandardError] the converted error

      # @!method result
      #  Signature for the &result callback provided to a {converter} block
      #  @return [Object] simple json object parsed from the response result
      #  @raise [JsonRpcKit::Error, NoMethodError, ArgumentError, JSON::ParserError] from the error embedded in the
      #    response

      # Dispatches a JSON-RPC request to the given &{.transport} block
      # @param method [String] the JSON-RPC method name
      # @!macro invoke_params
      # @yield [id, request_json, **request_opts, &response] the &{transport} to send the request and handle
      #   the response
      def invoke(method, *args, rpc_notify: false, **kwargs, &transport)
        id = next_id unless rpc_notify

        tp_opts = extract_rpc_options(kwargs)

        request_json = to_request(id, method, args, kwargs)
        transport.call(id, request_json, **tp_opts) do |response, **response_opts, &result|
          from_response(response, **response_opts, &result)
        end
      end

      private

      def to_request(id, method, args, kwargs)
        raise ArgumentError, 'Use either positional or named parameters, not both' if args.any? && kwargs.any?

        params = nil
        params = args if args.any?
        params = kwargs if kwargs.any?

        { jsonrpc: '2.0', method: method, params: params, id: id }.compact.to_json
      end

      def from_response(response, content_type: CONTENT_TYPE, **resp_opts, &result)
        raise JSON::ParserError unless content_type == CONTENT_TYPE

        return result.call(**resp_opts.transform_keys! { |k| "rpc_#{k}" }) { from_response(response) } if result

        response = parse(response, content_type:, error_class: InvalidResponse)

        return response[:result] unless response[:error]

        Error.raise_error(response[:error])
      end
    end

    # Create a JSON-RPC endpoint.
    #
    # The supplied block represents the transport layer, responsible for dispatching requests and resolving
    # responses.
    #
    # @param namespace [String] optional namespace prefix used to convert ruby method names to JSON-RPC convention
    # @yield [id, request_json, **request_opts, &response] the {.transport} to send requests and handle responses
    def initialize(namespace: nil, &transport)
      @transport = transport
      @namespace = namespace
    end

    # Redirects all method calls to {#json_rpc_invoke}
    def method_missing(...)
      json_rpc_invoke(...)
    end

    # Fire and forget notification (ie does not get a response)
    # @return [void]
    def json_rpc_notify(method, *, **)
      json_rpc_invoke(method, *, rpc_notify: true, **)
      nil
    end

    # Convention to return a transport-specific future/promise
    def json_rpc_async(method, *, **, &)
      json_rpc_invoke(method, *, rpc_async: true, **, &)
    end

    # Invokes JSON-RPC via the transport block provided to {#initialize}
    # @overload json_rpc_invoke(method, *args, **kwargs, &converter)
    #  @param method [Symbol|String] the RPC method to invoke. A Symbol is converted with {ruby_to_json_rpc} using
    #    the namespace optionally provided to {#initialize}.
    #  @!macro invoke_params
    #  @option kwargs [String, nil] :rpc_namespace for (Symbol) method, overriding the default namespace
    #    provided to {#initialize}
    #  @yield [**resp_opts, &result] optional block to convert the simple json response result or error,
    #    overriding any {.converter} provided by the transport.
    def json_rpc_invoke(method, *, rpc_namespace: @namespace, **, &converter)
      method = ruby_to_json_rpc(method, namespace: rpc_namespace) if method.is_a?(Symbol)
      self.class.invoke(method, *, **) do |id, json, **rpc_options, &response|
        transport.call(id, json, **rpc_options) do |resp_json, **resp_opts, &tp_converter|
          response.call(resp_json, **resp_opts, &converter || tp_converter)
        end
      end
    end

    private

    attr_reader :transport

    def respond_to_missing?(_method, _include_private = false)
      true
    end
  end
end
