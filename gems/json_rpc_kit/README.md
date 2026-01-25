# JsonRpcKit

A transport-agnostic JSON-RPC 2.0 toolkit for Ruby that provides both client and server components.

## Features

- **Transport Agnostic**: Works with HTTP, WebSocket, MQTT, or any custom transport
- **Client Endpoint**: Method missing magic for natural Ruby method calls
- **Server Service**: Include module to make any Ruby object JSON-RPC capable
- **Ruby Semantics**: Automatic snake_case to camelCase conversion
- **Error Handling**: JSON-RPC error hierarchy

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'json_rpc_kit'
```

## Usage

### Client (Endpoint)

Create an endpoint with a transport block and invoke methods

```ruby
require 'json_rpc_kit'

# Create endpoint with optional namespace, and a block that handles the transport
endpoint = JsonRpcKit.endpoint(namespace: 'users') do |id, request_json, **opts, &response|
  # Your transport implementation here
  # HTTP: http_post(request_json, **opts, &response)
  # MQTT: mqtt_request(request_json, **opts, &response)
  # etc.
end

# Make JSON-RPC calls using method missing and ruby method name conventions
result = endpoint.get_user(123) # > { "method" : "users.getUser", "params" : [ 123 ] }
users = endpoint.list_users(limit: 10)  # > { "method" : "users.listUsers", "params": { "limit" : 10 } }

# Notifications (fire and forget) > { "method" : "system.logEvent", "params" : { "message" : "Hello"} }
endpoint.log_event!(message: "Hello")  # Bang method for notifications
endpoint.json_rpc_notify(:log_event, message: "Hello")

# Transport options via #with
endpoint.with(timeout: 30).get_user(123)
endpoint.with(async: true).slow_operation(data: "...")
```

Asynchronous calls if supported by the transport
```ruby

endpoint = JsonRpcKit.endpoint do |id, request_json, async: false, timeout: nil, &response|
  # Some transport that returns a future/promise and can carry a Proc to resolve value/error from the response string
  future = http_post_async(request_json) { |response_json| response.call(response_json) }
  
  # just return the future if async requested
  next future if async
  
  # otherwise wait for the result, with optional timeout
  future.wait(timeout).value
end

# Async calls (returns transport-specific future/promise)
future = endpoint.json_rpc_async(:next_id, :slow_operation, data: "...")
# ... do some other work in the meantime ...
future.then { |result| puts result }
```

### Server (Service)

```ruby
require 'json_rpc_kit'

class UserService
  include JsonRpcKit::Service
  
  json_rpc_namespace 'users' # Set current default namespace
  
  # Explicitly bind methods to JSON-RPC method names
  def get_user(id)
    # Your implementation
    { id: id, name: "User #{id}" }
  end
  json_rpc :get_user # => "users.getUser"

  def list_users(limit: 10)
    # Your implementation
    (1..limit).map { |i| { id: i, name: "User #{i}" } }
  end
  json_rpc :list_users # => "users.listUsers"
end

# Handle JSON-RPC request
service = UserService.new

request_json, content_type = # Whatever your transport layer is to receive JSON-RPC request string
response_json = service.json_rpc_serve(request_json, content_type:)
```

### Transport Integration

The gem provides the protocol layer - you find a transport that is already integrated or implement one yourself:

```ruby
# Integrated MQTT transport example

# Get an MQTT V5 client, with Request/Response features enabled
require 'mqtt/v5'
client = MQTT.open('mqtt://...', request_response_information: true)
# Start an endpoint that sends requests to a service topic
endpoint = client.json_rpc_endpoint('service/api-v1')

# DIY HTTP transport example
endpoint = JsonRpcKit::Endpoint.new do |id, request_json, timeout: 30, content_type:, **opts, &response|
  http_response = Net::HTTP.post(uri, request_json,
                                 'Content-Type' => content_type, # 'application/json'
                                 'Timeout' => timeout
  )
  response.call(http_response.body)
end

endpoint.list_users #> Call JSON-RPC listUsers method over the configured transport
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
