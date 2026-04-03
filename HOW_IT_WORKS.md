How It Works
============

This document explains the internal architecture that supports the {MQTT::Core::Client} API, bridging the simplified publish/subscribe interface with the underlying MQTT protocol requirements.

## Architecture Overview

The library separates concerns into distinct layers:

- **{MQTT::Core::Client}** - User-facing API for publish/subscribe operations
- **{MQTT::Core::Client::Session}** - MQTT protocol state management (packet IDs, QoS flows)
- **{MQTT::Core::Client::SessionStore}** - Persistence layer for QoS guarantees
- **{MQTT::Core::Client::Connection}** - Network I/O and packet serialization
- **{ConcurrentMonitor}** - Thread/Fiber abstraction for concurrency

## Client Lifecycle

The Client tracks both its own state and the underlying socket connection state:

```
Client:     :configure → :disconnected ⇄ :connected → :stopped
                              ↓              ↑
Connection:              [connecting] → [established] → [closed]
                              ↑______________|  (reconnect)
```

- **:configure** - Initial state, event handlers and options are set
- **:disconnected** - No active socket connection, may be attempting to connect/reconnect
- **:connected** - Socket established and `CONNACK` received, can publish/subscribe
- **:stopped** - Terminal state after explicit disconnect, no further operations allowed

## Session: MQTT Protocol State

The Session implements MQTT protocol requirements that are abstracted away from the Client API:

### Packet Identifiers
- Assigns unique IDs to `PUBLISH` (QoS 1/2), `SUBSCRIBE`, and `UNSUBSCRIBE` packets
- Tracks in-flight packets awaiting acknowledgement
- Releases IDs when protocol flows complete

### QoS Protocol Flows

The Session manages the multi-packet exchanges required by QoS 1 and QoS 2. See the MQTT specifications for protocol details. The Session only manages the protocol-level `SUBSCRIBE`/`UNSUBSCRIBE` packet flows and their acknowledgements.

### Birth-Phase Buffering

When reconnecting to an existing session (eg via {MQTT::Core::Client::FilesystemSessionStore}), the broker
may send queued messages immediately after `CONNACK`, before the `on_birth` handler has finished
re-establishing subscriptions. The Session buffers all received `PUBLISH` packets during the birth phase
and replays matching packets to each subscription as it is registered. The buffer is cleared when
`on_birth` completes.

### Session Persistence and clean_session/clean_start

The MQTT protocol distinguishes between the network Connection and the logical Session. The `clean_session` (MQTT 3.1.1) or `clean_start` (MQTT 5.0) flag in `CONNECT` and the `session_present` flag in `CONNACK` coordinate whether client and broker agree on resuming existing session state.

**This library's approach:**

The SessionStore determines session behavior based on its persistence capabilities:

**{MQTT::Core::Client::Qos0SessionStore}**
- Only supports QoS 0 (no acknowledgements needed)
- Always sends `clean_session=true` - no session state to preserve
- Each connection is independent

**{MQTT::Core::Client::MemorySessionStore}**
- Stores session state in memory
- First connection: sends `clean_session=true` (no prior state)
- Reconnection within same process: sends `clean_session=false` to resume
- Session ends when: explicit disconnect, retry handler gives up, or offline longer than `expiry_interval`

**{MQTT::Core::Client::FilesystemSessionStore}**
- Persists session state to disk (identified by `client_id`)
- Sends `clean_session=false` to resume previous session (even across process restarts)
- Session ends when: explicit disconnect, retry handler gives up, or offline longer than `expiry_interval`

**Broker Agreement via session_present:**

When `clean_session=false`, the broker responds with `session_present` in `CONNACK`:
- `session_present=true`: Broker has the session, client retransmits unacknowledged packets
- `session_present=false`: Broker has no session (expired or never existed), client starts fresh

The Session automatically raises {MQTT::SessionNotPresent} if it expected to resume but the broker disagrees, and {MQTT::SessionExpired} if the session expires before reconnection.

This removes the burden from application developers to coordinate these flags with their persistence strategy.

## SessionStore: QoS Guarantees

The SessionStore determines what QoS guarantees can be met:

- **{MQTT::Core::Client::Qos0SessionStore}** - No persistence, QoS 0 only
- **{MQTT::Core::Client::MemorySessionStore}** - In-memory, survives network dropouts
- **{MQTT::Core::Client::FilesystemSessionStore}** - Disk-based, survives process restarts

The SessionStore provides:
- `client_id` and `expiry_interval` for `CONNECT` packet
- Storage/retrieval of unacknowledged outbound packets for retry on reconnect
- QoS 2 inbound deduplication state (packet IDs awaiting PUBREL)
- `clean_session`/`clean_start` flag determination

QoS 2 guarantees exactly-once *delivery* at the protocol level — the broker will not send duplicate
messages to the client's receive loop. The library does not attempt to track application-level
message handling. Applications requiring exactly-once *processing* should implement idempotent
message handlers.

## Connection: Network I/O

The Connection manages the TCP/TLS socket and MQTT packet framing:

### CONNECT Handshake
1. Opens socket via {MQTT::Core::Client::SocketFactory}
2. Sends `CONNECT` packet with Session parameters
3. Receives `CONNACK` with broker's session state
4. Starts send/receive loops

### Send Loop
- Reads packets from the send queue
- Serializes to wire format
- Sends `PINGREQ` for keep-alive
- Exits on `DISCONNECT` or EOF

### Receive Loop
- Deserializes packets from socket
- Routes to Session for protocol handling
- Delivers `PUBLISH` to matching Subscriptions
- Completes {MQTT::Core::Client::Acknowledgement} for request/response flows
- Exits on socket EOF

### Version-Specific Handling
- **MQTT 3.1.1**: Basic protocol flows
- **MQTT 5.0**: Enhanced features (properties, reason codes, `AUTH` packets, flow control quotas)

## Concurrency Model

{ConcurrentMonitor} provides a unified abstraction over Thread and Fiber concurrency:

- **Thread::Monitor** - Standard Ruby threads with MonitorMixin
- **Async::Monitor** - Fiber-based via the `async` gem

### Handling Asynchronous Message Delivery

MQTT is inherently asynchronous - subscribed messages arrive unpredictably from the broker. Different language ecosystems handle this differently:

**Callback-based (Java, Python, Go, C/C++):**
- Register a callback/listener function when subscribing
- Callback invoked on a background thread when messages arrive
- Developer must handle thread safety and message queuing
- Messages may be dropped if callback blocks or is slow

**Event-based (JavaScript/Node.js):**
- Event emitter pattern: `client.on('message', handler)`
- Natural fit for event loop architectures

**This library's Ruby-idiomatic approach:**

{MQTT::Core::Client::Subscription} objects are **Enumerable** - treating message streams as lazy iterators:

```ruby
# Blocking iteration - processes messages as they arrive
client.subscribe('topic/#').each { |topic, payload| process(topic, payload) }

# Take first N messages then automatically unsubscribe
client.subscribe('topic/#').take(5).each { |topic, payload| ... }

# Async processing in a background task
client.subscribe('topic/#').async { |topic, payload| process(topic, payload) }
```

**Key differences:**
- Messages are queued internally, not dropped if processing is slow
- Enumeration blocks until unsubscribe or disconnect
- Explicit control over concurrency via `#async` or manual task creation
- Subscription lifecycle tied to the Enumerable object

The Client tracks active {MQTT::Core::Client::Subscription} objects and routes received `PUBLISH` packets
to matching subscriptions via {MQTT::Core::Client::MessageRouter}. The MessageRouter uses a
{MQTT::Core::Client::MessageRouter::Trie Trie} (prefix tree) for efficient wildcard topic matching,
and for MQTT 5.0 clients, can route by subscription identifier when supported by the broker.

### Concurrent Tasks

Multiple tasks run concurrently within a Client:

1. **User tasks** - Call `#publish`, `#subscribe` from any task
2. **Connect task** - Manages connection lifecycle and reconnection
3. **Send task** - Serializes packets to socket
4. **Receive task** - Deserializes packets from socket, routes to Subscriptions
5. **Subscription tasks** - Process received messages via {MQTT::Core::Client::EnumerableSubscription#async}

### Synchronization

- **Send Queue** - Multiplexes requests from user tasks to send task
- **Subscription Queues** - Buffer messages for each active Subscription
- **Acknowledgement** - Blocks user task until response received
- **Monitor** - Protects shared state (Session, Subscriptions, status)

User tasks calling `#publish` (QoS 1/2) or `#subscribe` block until the broker acknowledges, ensuring the protocol flow completes before returning.

## Packets

Packets are immutable data structures that represent MQTT protocol messages:

- Essentially a Hash of simple types (Strings, Integers, Arrays) matching MQTT protocol types
- Defined using metaprogramming via {MQTT::Core::Type::Shape} DSL
- Type system ({MQTT::Core::Type}) handles serialization/deserialization of protocol types:
  - Fixed-width integers (Int8, Int16, Int32)
  - Variable-length integers (VarInt)
  - UTF-8 strings with length prefixes
  - Binary data
  - Bit flags
  - Lists and nested structures
- Initialized from keyword arguments or deserialized from IO
- Serialized to binary wire format for transmission
- Version-specific fields and validation
- Properties (MQTT 5.0) handled via {MQTT::Core::Type::Properties}

## Error Handling

Protocol errors are raised as {MQTT::ResponseError} subclasses based on reason/return codes from broker acknowledgements (`CONNACK`, `SUBACK`, `PUBACK`, etc.).

Network errors trigger the `on_disconnect` handler, which can retry via {MQTT::Core::Client::RetryStrategy}.
