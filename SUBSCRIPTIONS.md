# Subscription Handling

## Architecture

### Subscription

A `Subscription` is a mutable object that accumulates topic filters over time. Each call to
`Subscription#subscribe` sends a SUBSCRIBE to the broker and adds the confirmed filters.
Messages matching any of the subscription's filters are delivered to its handler.

```ruby
sub = client.subscribe('home/temperature')     # subscribe to one topic
sub.subscribe('home/humidity')                  # add another topic to the same subscription
sub.unsubscribe('home/temperature')             # remove one topic (partial unsubscribe)
sub.unsubscribe                                 # remove all topics and close the subscription
```

### MessageRouter

`MessageRouter` owns all routing state:
- `@subs` — `Hash<String, Set<Subscription>>` mapping filter strings to subscriptions
- `@topic_trie` — a Trie for efficient wildcard matching

Routing: exact topic lookup + Trie wildcard match → filter strings → `@subs[filter]` → Subscriptions.

V5 `MessageRouter` adds `SubscriptionIds` which tracks:
- `@filters_by_id` — `Hash<Integer, Set<String>>` (id → filters)
- `@ids_by_filter` — `Hash<String, Set<Integer>>` (filter → ids)

V5 routing with identifiers: id → filters → `@subs[filter]` → Subscriptions.
Filters are the shared hub between identifiers and subscriptions.

### Flow

**Subscribe:**
```
Subscription#subscribe → Client#subscribe! → yields SUBSCRIBE packet
  → MessageRouter#register (adds to @subs, trie, topic_filters; V5: tracks id→filters)
  → send SUBSCRIBE, wait SUBACK
```

**Unsubscribe:**
```
Subscription#unsubscribe(*filters)
  → MessageRouter#deregister (removes from @subs, trie, topic_filters; returns inactive filters)
  → Client#unsubscribe! only for inactive filters (not shared with other subscriptions)
  → put(nil) if no filters remain (terminates enumeration)
```

Deregistration happens before UNSUBSCRIBE is sent. See [Failure Modes](#failure-modes).

**Route:**
```
PUBLISH received → MessageRouter#route
  V3: matching_filters(topic) → @subs[filter] → deduplicated subscriptions
  V5 with ids: id → filters → @subs[filter] (+ trie fallback in non-strict mode)
  V5 without ids: matching_filters(topic) → @subs[filter] (strict: excludes id-tracked filters)
```

## Overlapping and Duplicate Filters

### Overlapping Filters (different filter strings matching the same topic)

Multiple subscriptions with different filters that match the same topic all receive the message:

```ruby
sub1 = client.subscribe('home/bedroom/temperature')
sub2 = client.subscribe('home/+/temperature')
sub3 = client.subscribe('home/#')

client.publish('home/bedroom/temperature', '20')
# All three subscriptions receive the message
```

**Retained message caveat:** Each SUBSCRIBE triggers the broker to send retained messages matching
that filter. With overlapping filters, the same retained message may be delivered multiple times
(once per overlapping SUBSCRIBE). V5 clients can use `retain_handling: 1` or `retain_handling: 2`
on the TopicFilter to control this at the protocol level.

### Duplicate Filters (same filter string in multiple subscriptions)

Allowed, but with caveats:

```ruby
sub1 = client.subscribe('home/temperature')
sub2 = client.subscribe('home/temperature')
# Both receive messages published to 'home/temperature'
```

1. **Retained messages** — the broker sends retained messages on each SUBSCRIBE, so both
   subscriptions receive them.
2. **Subscription options** — the broker maintains one subscription per filter. The second
   SUBSCRIBE updates the broker's options (QoS, etc.) which may affect the first.
3. **Unsubscribe interaction** — unsubscribing sub1 will not send UNSUBSCRIBE to the broker
   because sub2 still uses the filter. Unsubscribing sub2 will send UNSUBSCRIBE.

## V5 Subscription Identifiers

### Routing

Identifiers are automatically allocated for each `subscribe` call. The broker tags incoming
PUBLISH messages with the identifiers of matching subscriptions.

Routing goes through the filter as the shared hub: `id → @filters_by_id[id] → @subs[filter]`.
This means the same `@subs` map is used for both id-based and trie-based routing.

### Strict Mode

Controls how messages are delivered when subscriptions with and without identifiers overlap.

Mosquitto (and likely other brokers) sends separate PUBLISH messages per subscription identifier
match, plus one without identifiers for non-id subscriptions.

- `strict: false` (default) — messages with ids also fan out via the trie to non-id subscriptions.
  Suitable when the broker sends a single message with all matching ids.
- `strict: true` — messages with ids route only via id→filter→subs. Messages without ids
  exclude filters that have an associated identifier. Suitable for Mosquitto-style brokers that
  send separate messages per id.

### Identifier Lifecycle

- Allocated in `V5::Client#subscribe` before the SUBSCRIBE packet is built.
- Tracked in `SubscriptionIds` via `@filters_by_id` and `@ids_by_filter` at registration.
- Released when filters are deregistered (partial or full unsubscribe). An id is freed when
  all its associated filters have been removed.
- An id cannot be reused while any of its filters are still registered. Attempting to
  register an in-use id raises `MQTT::Error`.

## Failure Modes

### Deregister-before-unsubscribe

Filters are removed from routing before UNSUBSCRIBE is sent. If the UNSUBSCRIBE fails (network
error, broker rejection), the filter is already deregistered. Messages for that filter will not
be delivered even though the broker still thinks the subscription is active.

This is acceptable because:
- Network errors break the connection; reconnection re-establishes subscriptions via `on_birth`
- Broker rejections are protocol errors that should not occur in normal operation
- The alternative (deregister after UNSUBACK) risks delivering messages to a discarded subscription

### Concurrent subscribe/unsubscribe of the same filter

Concurrent subscribe and unsubscribe of the same filter from different Subscriptions is
undefined behaviour. Applications should serialize operations on the same filter or accept
that state may be inconsistent until the next reconnect.
