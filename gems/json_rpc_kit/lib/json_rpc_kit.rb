# frozen_string_literal: true

require_relative 'json_rpc_kit/helpers'
require_relative 'json_rpc_kit/version'
require_relative 'json_rpc_kit/errors'
require_relative 'json_rpc_kit/service'
require_relative 'json_rpc_kit/endpoint'

# A toolkit for building JSON-RPC services and making JSON-RPC requests
module JsonRpcKit
  CONTENT_TYPE = 'application/json'

  class << self
    # Invoke a JSON-RPC method.  Shortcut for {Endpoint.invoke}
    def invoke(...)
      Endpoint.invoke(...)
    end

    # Create an endpoint that can invoke JSON-RPC methods as natural ruby method calls.
    #   Shortcut for {Endpoint.initialize}
    # @return [Endpoint]
    def endpoint(...)
      Endpoint.new(...)
    end

    # Respond to a JSON-RPC request by calling a ruby method or block. Shortcut for {Service.serve}
    # @return [String] the JSON-RPC response
    def serve(...)
      Service.serve(...)
    end
  end
end
