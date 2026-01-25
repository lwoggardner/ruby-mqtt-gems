# frozen_string_literal: true

require_relative 'json_rpc_kit/helpers'
require_relative 'json_rpc_kit/version'
require_relative 'json_rpc_kit/errors'
require_relative 'json_rpc_kit/service'
require_relative 'json_rpc_kit/endpoint'

# A toolkit for nd making JSON-RPC requests (see {Endpoint} and building JSON-RPC services (see {Service}).
module JsonRpcKit
  CONTENT_TYPE = 'application/json'

  class << self
    # Create an endpoint that can invoke JSON-RPC methods as natural ruby method calls.
    #   Shortcut for {Endpoint.initialize Endpoint.new}
    # @return [Endpoint]
    def endpoint(...)
      Endpoint.new(...)
    end

    # Create a service transport handler for processing JSON-RPC requests.
    #   Shortcut for {Service.transport}
    # @return [Proc] Handler proc for processing requests
    def service_transport(...)
      Service.transport(...)
    end
  end
end
