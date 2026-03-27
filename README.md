ruby-mqtt-gems
==============

A set of pure Ruby gems that implements the [MQTT] protocol, a lightweight protocol for publish/subscribe messaging.

These are inspired by, but not at all compatible with, the original [njh/ruby-mqtt].

Installation
------------

## Gems

Add the requisite gem(s) to your [Bundler] `Gemfile`:

- `mqtt-v5` - MQTT 5.0 protocol implementation
- `mqtt-v3` - MQTT 3.1.1 protocol implementation

```ruby
gem 'mqtt-v5', :github => 'lwoggardner/mqtt-v5' # using github for gems is not really practical
```

Quick Start
-----------

```ruby
require 'mqtt/core'

MQTT.open('test.mosquitto.org') do |c|
  # c => MQTT Client (version determined by broker capabilities)
  
  # Connect to the broker, passing will message settings etc
  c.connect(will_topic: 'some/topic', will_payload: 'just resting')
  
  # Publish a message to a topic
  c.publish('test/topic','message')

  # Subscribe and wait for a single response (automatically unsubscribed)
  topic, message = c.subscribe('test/sub').each.first
  
  # Subscribe and handle messages in a new thread
  c.subscribe('test/feed').async { |topic, payload| process(topic, payload) }
  
  # Subscribe and handle messages in this thread, exiting when receive 'offline' message
  c.subscribe('test/status').each { |topic, payload| break if payload == 'offline' }
end
```

Usage
----------------

### MQTT Protocol Version  ###

This library supports both MQTT 3.1.1 (v3) and 5.0 (v5) with a unified interface.

Pub/Sub code written for v3 is compatible with v5, and this is recommended unless specific v5 features are required.

At runtime, `mqtt/v5` will be preferred over `mqtt/v3`,

| Configuration                | Version agnostic        | Requires v5 features |
|------------------------------|-------------------------|----------------------|
| **Gem dependencies**         | `mqtt-v3` and `mqtt-v5` | `mqtt-v5` only       |
| **Require**                  | `require 'mqtt/core'`   | `require 'mqtt/v5'`  |
| MQTT.open(protocol_version:) | _not set_               | `5`                  |


### Configuration - MQTT.open ###

See {MQTT.open} for a full list of options.

#### Connection options ####
The network connection is configured by passing either a [MQTT URI] or host and port information to {MQTT.open}

```ruby
client = MQTT.open('mqtt://myserver.example.com')
client = MQTT.open('mqtts://appuser@myserver.example.com?password_file=/secrets/appuser.secret')
client = MQTT.open('mqtt.example.com')
client = MQTT.open('mqtt.example.com', 18830)
client = MQTT.open('unix:///var/run/mosquitto.sock')
```

SSL/TLS options, including client certificates, are supported.
```ruby
# Use default SSL options, just use 'mqtts' URI scheme
client = MQTT.open('mqtts://mqtt.example.com')

# With client certificate for authentication
ssl = {
  ssl_cert_file: path_to('client.pem'),
  ssl_key_file: path_to('client.key'),
  ssl_passphrase: read_passphrase,
  ssl_ca_file: path_to('server-ca.pem')
}
client = MQTT.open('mqtts://mqtt.example.com', **ssl)
```

#### Session options ####

The MQTT Session manages QoS guarantees for the Client.  The properties to select and configure the Session and setup
connection retries are also configured in {MQTT.open}.  See [Session Management](#session_management)

#### URI configuration ####

A fully flexible client application can just use the `MQTT_SERVER` environment variable with connection and session
configuration options encoded entirely in the [MQTT URI] query string.

```ruby
# ENV['MQTT_SERVER'] # => 'mqtts://myapp@host.example.net:48830?protocol_version=5,ssl_ca_file=ca.pem&client_id=device1'
client = MQTT.open
```

In cases where the uri is provided from an untrusted source, properties from the query string can be ignored 
```ruby
ssl_options = { ssl_min_version: :TLSv1_2 }
connect_options = { password_file: '/etc/secrets/mqtt.password' }
client = MQTT.open(untrusted_uri, ignore_uri_params: true, **ssl_options, **connect_options)
```

#### Block semantics ####
As per ruby `open` semantics, the client can be instantiated with a block, so that when the block completes, 
disconnection is ensured.

```ruby
MQTT.open('test.mosquitto.org') do |client|
   # use `client` for #publish, #subscribe
end
# client(:disconnected)
```
Or without a block, and control disconnection yourself.
```ruby
client = MQTT.open('test.mosquitto.org')
   # use `client` for #publish, #subscribe
client.disconnect
```

### Connecting to the broker ###

A new {MQTT::Core::Client} instance is created with status `:configure` and not yet connected, allowing
low-level configuration and event handlers to be installed where required.

{MQTT::Core::Client#connect} then takes keyword arguments aligned to the version-specific `CONNECT` packet, to complete its
construction. For example:
* authentication information, if not provided as part of the connection URI.
* the optional 'will' message to send on disconnect.
* v5 connection properties

It then starts the connection and blocks until the `CONNACK` response is received from the broker.

```ruby
MQTT.open('mqtt://mqtt.example.org', connect_timeout: 5, **connect) do |client|
  client.status                    # => :configure
  client.on_birth { puts 'birth' } # install birth handler (session established - persistent async subscriptions)
  
  # Connect 
  client.connect(will_topic: 'some/topic', will_payload: 'just resting')
  client.status                    # => :connected
  # ..publish, subscribe etc.. blocking until done
end
```

### Publishing ###

{MQTT::Core::Client#publish} takes arguments to construct the version-specific `PUBLISH` packet and send it to the broker.

```ruby
# Simple publish
client.publish(topic, payload)

# Publish with QOS, retain etc..
client.publish('test/topic','message', qos: 2, retain: true)
```

* QOS 0 publish is the default and will return immediately
* QOS 1 and 2 will only return once fully acknowledged by the broker.

QOS 1/2 packet_identifiers, control flow and message retries are handled automatically via [Session Management](#session_management)

### Subscriptions ###

{MQTT::Core::Client#subscribe} takes arguments to construct the version-specific `SUBSCRIBE` packet, sends it to 
the broker, waits for the `SUBACK` response, and returns a {MQTT::Core::Client::EnumerableSubscription}.

```ruby
sub = client.subscribe('topic1','topic2', 'prefix/#') # => #<MQTT::Client::EnumerableSubscription
```

#### Subscription errors

Default behaviour is to raise an exception if any topic filter in a `SUBSCRIBE` request
is not fully accepted by the broker as indicated by the `SUBACK` response.

{MQTT::Core::Client#subscribe} adds the options `:ignore_failed` and `:ignore_qos_limited` to control this 
behaviour.

The `on_subscribe` event can be used to further interrogate the `SUBSCRIBE` and `SUBACK` packets,
eg for logging purposes.

```ruby
# request qos level for the subscription to 2, but ignore if broker does not allow
client.on_subscribe do |subscribe, suback|
  filter_status = subscribe.filter_status(suback) # => { success: ['prefix/#'], qos_limited: [], failed: [] }
  #... log, etc  
end

sub = client.subscribe('prefix/#', max_qos: 2, ignore_qos_limited: true)
```

#### Processing Received Messages ####

{MQTT::Core::Client::EnumerableSubscription#each} iterates over matching `PUBLISH` messages as they arrive from the
broker and until it is unsubscribed or the client is disconnected.

Messages are deconstructed into topic, payload, and a keyword Hash of the other packet attributes.

```ruby
# #each with a block iterates over all messages
sub = client.subscribe('topic1','topic2', 'prefix/#')
  
sub.each { |topic, payload| puts payload }
#... blocked here until another thread unsubscribes or disconnects

# block sent to #each can exit the enumeration via normal break
sub.each do |topic, payload|
  break if payload == 'offline'
  process(topic, payload)
end
# blocked here until receive an 'offline' message.

# Enumerable methods return results immediately
sub.take(5)  # => Array of 5 messages
sub.first    # => First message [topic, payload, attrs]

# Advanced lazy chaining for complex transformations
sub.lazy.select { |t, p| p.size > 100 }.map { |t, p| JSON.parse(p) }.take(5).to_a
# lazy chains must be materialized with .to_a or similar
```

The above examples are blocking in the calling thread. {MQTT::Core::Client::EnumerableSubscription#async} provides a means to process
received messages in a new thread.

```ruby
# #async iterates over messages in a new asynchronous task
sub, task = client.subscribe('topic/x').async { |topic, payload| process(topic, payload) }
# ... other code...
# then unsubscribe to finish iterating which will end the thread
sub.unsubscribe
task.join
```

Alternatively, {MQTT::Core::Client#async} can be used to start new threads
```ruby
task = client.async do
  client.subscribe('topic/x').map { |topic, payload| JSON.parse(payload) }.take(5)
end
# ... other code...
task.join
```

Subscriptions that process events for the lifetime of a session should be established in the
`on_birth` event handler to ensure proper [Session Management](#session_management) and recovery when reconnecting.

#### Unsubscribing ####

{MQTT::Core::Client::Subscription#unsubscribe} is the preferred way to unsubscribe.  After deactivating the Subscription with
the Client, topic filters originally used in the `SUBSCRIBE` packet, but excluding any  still in use in other active
Subscriptions, are unsubscribed from the broker.

The bang(!) methods on {MQTT::Core::Client::Subscription} and {MQTT::Core::Client::EnumerableSubscription} are shorthand
that wrap their standard counterparts in an 'ensure' block that calls `#unsubscribe`

Code that is enumerating messages via {MQTT::Core::Client::EnumerableSubscription#each} can also throw `:unsubscribe`

```ruby
sub = client.subscribe('topic1', 'topic2', 'prefix/#')

# explicitly unsubscribe
sub.unsubscribe

# via #each and throw :unsubscribe
sub.each do |topic,payload|
  throw :unsubscribe if payload == 'offline'
  process(topic, payload)
end

# via #each! and ending enumeration via break
sub.each! do |topic, payload|
  break if payload == 'offline'
  process(topic, payload)
end
# now unsubscribed

client.subscribe('topic1', 'topic2', 'prefix/#').tap! do |sub2|
  # ... fun with sub2
end 
# sub2(:unsubscribed)

# automatically unsubscribed after receiving 5 messages via bang suffix method
messages = client.subscribe('topic/x').take!(5)
```

### Disconnecting ###

{MQTT::Core::Client#disconnect} can be called directly from any thread holding the Client.

An explicit disconnect will wait for pending QOS flows to complete before disconnecting from the broker.

No further calls can be made to the client once the disconnect process has started,

### Error handling ###

`#connect`, `#publish`, `#subscribe` will block and raise {MQTT::Error} and its subclasses based on the acknowledged
response from the broker.

Protocol-specific errors returned in acknowledgement packets (`SUBACK`, `PUBACK`, etc...) are subclasses of
{MQTT::ResponseError} aligned with reason or return codes as per the MQTT specifications.

### Session Management ###

The client handles session management automatically, and this behaviour is normalised between v3 and v5 clients.

#### Session Stores ####

The type of session store determines the extent to which QoS 1 and 2 guarantees can be met.

| Feature           | {MQTT::Core::Client::Qos0SessionStore} | {MQTT::Core::Client::MemorySessionStore} | {MQTT::Core::Client::FilesystemSessionStore}  |
|-------------------|----------------------------|------------------------------|-----------------------------------|
| Storage Type      | In-memory                  | In-memory                    | File-based persistence            |
| QoS               | QoS0 only                  | QoS 2                        | QoS 2                             |
| Resilience        | Not applicable             | In process network dropouts  | Network errors, Process restart   |
| Memory Usage      | Inflight packet ids only   | Inflight packet data         | Inflight packet data              |
| Disk Usage        | None                       | None                         | Inflight packet data              |
| Performance       | Fast                       | Fast                         | Slow - synchronized disk I/O      |
| Configuration     | None                       | Expiry interval only         | File path / storage configuration |
| - client_id:      | Anonymous (*1)             | Server assigned (*1)         | Explicit client_id required       |
| - expiry_interval | Not Applicable (0)         | > 0, nil = never expire (*2) | > 0, nil = never expire (*2)      |
| Recovery          | Not Applicable             | Automatic (in process)       | Automatic (across restarts)       |
| Cleanup           |                            |                              | Expired Sessions                  |
| `.open` Option    | _default_                  | `:session_expiry_interval`   | `:session_base_dir`               |

* (*1) The default client_id is an empty string, which is treated as anonymous or server-assigned. Using `nil`
  will generate a random client_id.  
* (*2) Setting expiry_interval to nil is actually 0xFFFFFFFF = 136 years. A v5 broker can reply via CONNACK
  with a shorter value. A v3 broker will just silently discard old sessions however it likes.

Recommendation:
* {MQTT::Core::Client::Qos0SessionStore} for applications that do not require QoS 1 or 2 guarantees
* {MQTT::Core::Client::MemorySessionStore} for testing or when it is ok to lose messages while the client is offline
* {MQTT::Core::Client::FilesystemSessionStore} if QoS guarantees need to survive across restarts

**Note on QoS 2 and application-level guarantees:**
QoS 2 guarantees exactly-once *delivery* at the protocol level — the broker will not send duplicate messages
to the client's receive loop. However, if the application crashes after receiving a message but before completing
processing, the broker considers the message delivered. Applications requiring exactly-once *processing* should
implement idempotent message handlers (e.g. deduplication by message content or correlation ID).


```ruby

# Where message loss is acceptable when app is offline/restarting use memory session store with no expiry.
# Retries are enabled automatically
client = MQTT.open(*io_args, session_expiry_interval: nil, **options)
client.session_store # => MQTT::Client::MemorySessionStore with no expiry

# If QoS guarantees need to survive across restarts, use a file-based session store with fixed client_id and
session_opts = { client_id: ENV['HOSTNAME'], session_base_dir: '/data/mqtt', session_expiry_interval: 86400 }
client = MQTT.open(*io_args, retry_strategy: true, **session_opts)
client.session_store # => MQTT::Client::FilesystemSessionStore with 1 day expiry
```


The session store can be set explicitly via the `:session_store` property sent to {MQTT.open}, or selected implicitly
via the presence of `:session_base_dir` or `:session_expiry_interval` options as per the above table.

The `CONNECT` properties `client_id:`, `session_expiry_interval:`, `clean_session` (v3) / `clean_start` (v5) flags
are injected automatically.

When the client and broker agree they have re-established a Session, any unacknowledged QoS1/2 packets in the
SessionStore are automatically re-sent to the broker.

#### Automatic Reconnection ####

In order for Session management to be useful, the client needs to be able to re-connect to the broker after a
network dropout.

{MQTT.open} will configure the default retry strategy by default if QoS 1/2 session store is configured.

{MQTT::Core::Client#configure_retry} installs a {MQTT::Core::Client::RetryStrategy} as the `on_disconnect` event handler to rescue certain
protocol and network errors and retry using an exponential backoff delay algorithm.

```ruby
MQTT.open('mqtt://mqtt.example.org') do |client|
  client.configure_retry # max_attempts: 0, base_interval: 1, max_interval: 300, jitter: 25
  client.connect
  # ...
end

# or via :retry_strategy option to .open
client = MQTT.open(retry_strategy: true)
# or via URI properties
client = MQTT.open('mqtt://localhost?retry_max_attempt=5')
```

A warning is logged unless the {MQTT::Core::Client::Qos0SessionStore} is used OR a retry_strategy is configured to indicate that QoS
guarantees are not met by default.

Sessions that do not successfully reconnect before they expire will stop retrying and raise {MQTT::SessionExpired}.

A reconnect that is trying to maintain an existing session but receives a `CONNACK` without `sesssion_present` set
will also stop retrying and raise {MQTT::SessionNotPresent}.

#### `on_birth` Event Handler ####

All persistent subscriptions that are expected to survive reconnection should be established with asynchronous
processing from the `on_birth` event handler. Do not block in this handler.

For QoS0SessionStore every re-connection establishes a new Session. At disconnect active subscriptions are cancelled,
and after reconnecting the `on_birth` event handler will be called again where the user code can re-establish them.

For QoS1 or QoS2 subscriptions, the broker may be expected to queue messages while the client is
disconnected and will start to forward them as soon as the client reconnects.

For a temporary network dropout this is OK, because the Client and Session instances still exists and Subscriptions are
still active, ready to receive the queued messages.

However, after a crash or maintenance shutdown, a restarted Client using an existing Session via 
{MQTT::Core::Client::FilesystemSessionStore} will be a new instance with no active Subscriptions. The queued messages may arrive before
the required Subscriptions are established.

To solve for this, until the `on_birth` event handler completes, the Client caches all received `PUBLISH` packets
in memory, delivering them to any new Subscriptions that match. At completion the cache is cleared, and the client
will resume normal operation, delivering messages to only active matching Subscriptions.

When using MemorySessionStore, the first connection is always a new Session, so there will be no queued
messages. Defining QoS1 or QoS2 subscriptions in the `on_birth` handler is not strictly necessary but still recommended,
while noting that the consistency guarantees are only met while the Client is alive.

```ruby
MQTT.open('mqtt://mqtt.example.org') do |client|
    client.on_birth { |client|
      # async handlers so this event is not blocked.
      client.subscribe('topic1','topic2', 'prefix/#', max_qos: 2).async { |topic, payload| process(topic, payload) }
    }
    client.connect
    # ...
end
```

### V5 Specific Features ###

#### Subscription Identifiers ####

Subscription Identifiers provide more efficient matching of incoming PUBLISH messages to registered Subscriptions,
offloading the bulk of the matching logic to the broker.

Identifiers are automatically allocated by default for all subscriptions for a V5 Client, if the broker
indicates it supports them.

This behaviour can be disabled entirely or on a per-subscription basis.  Explicit allocation is also available where
required - eg to ensure the same identifier is used when restarting a persistent session. 

When subscriptions with and without identifiers overlap, brokers differ in how they deliver messages.
Mosquitto sends separate `PUBLISH` messages per identifier match, while HiveMQ sends a single message
with all matching identifiers.  The `subscription_identifiers_strict` connection option controls which
behaviour the client expects:

```ruby
# Mosquitto-style brokers (default for localhost mosquitto)
client = MQTT.open('mqtt://localhost?subscription_identifiers_strict=Y')

# HiveMQ-style brokers (single PUBLISH with all ids)
client = MQTT.open('mqtt://broker.hivemq.com')
```

See {MQTT::V5::Client#subscribe}, {MQTT::V5::Client::MessageRouter::SubscriptionIds}

#### Topic Aliases ####

Topic Aliases are a bandwidth management feature that allows topics to be represented by a 2-byte integer rather
than the full-length string in both incoming and outgoing `PUBLISH` packets.

Incoming topic aliasing is managed by the `topic_alias_maximum:` property of the `CONNECT` packet. If
the broker chooses to provide topic aliases, then these are cached and resolved automatically on the client side so that
subscriptions etc see the full topic name from {MQTT::V5::Packet::Publish#topic_name}.

Outgoing topic aliasing is configured by the non-spec property `topic_alias_send_maximum:` sent to
{MQTT.open}.  If the broker supports topic aliases (via `CONNACK.topic_alias_maximum`) then aliases will be generated
automatically as messages are sent.
By default, a 'Least Recently Used' (LRU) policy is used to determine which aliases to keep in the limited size cache.

See {MQTT::V5::TopicAlias} for details.

#### Shared Subscriptions ####

Topics filter expressions in the form of `$share/<group>/<topic filter>` will receive messages as though they
were subscribed to `<topic filter>`.  Where multiple clients are subscribed in this way the broker will chose
one of them to receive the message.

#### Request / Response

Request/Response is a remote procedure call mechanism over MQTT. 

A request is a PUBLISH message with `:response_topic` and `:correlation_data` properties.  A subscription listens
on `:response_topic` for replies and uses `:correlation_data` to tie them back to the original request.

The CONNECT property `:request_response_information` helps negotiate wa prefix for the response topic
that is unique to the client session ({MQTT::V5::Client::Session#response_base).  Setting this property will
automatically start a subscription to handle responses and enable use of {MQTT::V5::Client#request} 
```ruby
# Request broker to negotiate a response topic prefix, and automatically subscribe to the response base topic prefix. 
client.connect(request_response_information: true)

# Then make requests...
result = client.request('service/hello', 'world') # => 'Hello world'
```

A response is a subscription that takes a message and publishes a result back to the received `:response_topic`,
reflecting the `:correlation_data` property.

This behaviour is encapsulated in {MQTT::V5::Client#response}
```ruby
client.response('service/hello') do |topic, request_payload|
  "Hello #{request_payload}"
end
```

Helpers to implement [JSON-RPC] over MQTT Request/Response are also available. See {MQTT::V5::Client::JsonRpc}

## Async Clients ##

{MQTT.async_open} provides a {MQTT::Core::Client} that uses fiber-based concurrency via the [async] gem.

The async client is recommended for:
* Managing many concurrent device connections (IoT gateways, device management)
* Your application uses the async gem ecosystem
* Fun!

The API is identical to that described for the Thread-based implementation above. The abstraction is provided by the
internal {ConcurrentMonitor} gem. For example {MQTT::Core::Client::EnumerableSubscription#async} returns a
{ConcurrentMonitor::Task} which in this case wraps an Async::Task rather than a Thread.

The async gem is not a transitive dependency of `mqtt/core` so you will need to explicitly add it to your application.

```ruby
require 'async'
require 'mqtt/core'

# Block form of open will start a reactor
client = MQTT.async_open('mqtt://mqtt.example.org') do |client|
  # mqtt things and async things
  sub, task = client.subscribe(*topics).async { |topic, payload| process(topic, payload) }
  task.join # wraps Async::Task#wait
end


client = MQTT.async_open('mqtt://mqtt.example.org') # => MQTT::V5::Async::Client
# Non-block form needs to use 'Sync' (from 'async' gem) to start the reactor externally before connect
Sync do
  client.connect
  # mqtt things and other async things
ensure
  client.disconnect
end
```

## Logging ##

Clients use a ruby ::Logger attached to the MQTT module.

```ruby
MQTT::Logger.log=($stdout) # or some other device
MQTT::Logger.log.debug!    # set debug logging

# or via URI properties
MQTT.open('mqtt://localhost?log_level=debug')
```

Principles
-----------------
* You are using Ruby so you are running on a full OS or container and not highly memory or CPU constrained.
  (ie this is not highly optimised for those things, or benchmarked for performance (yet))
* You might be running on an unreliable network.
* Packet field naming conforms to the OASIS MQTT specs converted to idiomatic ruby
* Packet field types are converted to natural Ruby types
* Operations block until acknowledged, exceptions are reported to the caller
* Opinionated session management with sensible defaults and warnings

## Differences to njh/mqtt

 * MQTT 5.0 support
 * QOS 2 support with volatile (in memory) or filesystem (persistent) session management
 * No support for MQTT S/N protocol
 * Packets are immutable structures, initialised from the keyword arguments hash
 * Optional re-connects to the server on network dropouts
 * Async (Fibered) or Threaded Clients
 * Requests block until acknowledged, raising Error if the ack is not successful
 * Subscriptions are enumerable, blocking, or non-blocking
 * Ruby 3.4+ required

### Migrating

Ask your favourite AI to do it for you?

Resources
---------

* API Documentation: http://rubydoc.info/gems/mqtt-core
* Protocol Specification v3.1.1: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html
* Protocol Specification v5.0:  https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html
* MQTT Homepage: http://www.mqtt.org/
* GitHub Project: http://github.com/lwoggardner/ruby-mqtt-gems


License
-------

Ruby-MQTT-Gems are licensed under the terms of the MIT license. See the file LICENSE for details.

Contact
-------

* Author:    Grant Gardner
* Email:     grant@lastweekend.com.au

[MQTT]:           http://www.mqtt.org/
[Rubygems]:       http://rubygems.org/
[Bundler]:        http://bundler.io/
[MQTT URI]:       https://github.com/mqtt/mqtt.github.io/wiki/URI-Scheme
[njh/ruby-mqtt]:  https://github.com/njh/ruby-mqtt
[async]:          https://github.com/socketry/async
[JSON-RPC]:       https://www.jsonrpc.org/specification