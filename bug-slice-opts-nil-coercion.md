# Bug: `slice_opts!` coerces `nil` values to `true` when slicing by prefix

## Summary

`Options#slice_opts!` uses `v || true` when extracting prefix-matched options, which silently converts `nil` values to `true`. This breaks any option where `nil` is a meaningful value, notably `session_expiry_interval: nil`.

## Affected Version

`mqtt-core` 0.9.0.rc1

## Location

`lib/mqtt/options.rb` line 19:

```ruby
opts.delete_if { |k, v| k.start_with?(prefix) && (s[k.to_s.delete_prefix(prefix).to_sym] = v || true) } if prefix
```

The same pattern exists on line 20 for `pattern:` matching.

## Discovery Context

Found while testing 0.9.0.rc1 gems in the `samil-inverter` project. The MQTT client is created in `lib/samil/cli/mqtt_options.rb`:

```ruby
def mqtt_client(mqtt_broker:)
  return nil unless mqtt_broker
  require 'mqtt/core'
  MQTT.async_open(mqtt_broker, session_expiry_interval: nil)
end
```

`session_expiry_interval: nil` is used intentionally — the inverter monitor only needs in-memory QoS sessions (no persistence across restarts), but wants the maximum expiry so sessions survive network blips. This worked with the 0.0.1 local gems but fails on 0.9.0.rc1.

## Reproduction

```ruby
MQTT.async_open('mqtt://localhost', session_expiry_interval: nil)
# => undefined method 'between?' for true (NoMethodError)
```

The `nil` is documented as valid — from `open.rb`:

```ruby
#   @option client_opts [Integer, nil] session_expiry_interval
#     - Set to nil to use maximum (130+ years) expiry
```

## Trace

```
session_expiry_interval: nil
  → slice_opts!(client_opts, :client_id, :session_store, prefix: 'session_')
  → prefix strip produces { expiry_interval: nil || true }  # => { expiry_interval: true }
  → MemorySessionStore.new(expiry_interval: true)
  → init_expiry_interval(true)
  → true.between?(0, MAX_EXPIRY_INTERVAL)  # => NoMethodError
```

## Suggested Fix

The `v || true` fallback is there to handle URI query parameter keys that have no value (e.g. `?clean_start` with no `=value`). But it also fires for explicitly passed `nil`.

One option — use `v.nil? ? true : v` only when the value originates from URI parsing, or change to a sentinel that distinguishes "key present with no value" from "key present with nil value":

```ruby
opts.delete_if { |k, v| k.start_with?(prefix) && (s[k.to_s.delete_prefix(prefix).to_sym] = v) } if prefix
```

If the `|| true` for bare URI params is still needed, it could be handled in the URI param extraction layer (`SocketFactory#query_params`) instead of in the general-purpose `slice_opts!`.

## Workaround

Pass the max value explicitly instead of `nil`:

```ruby
MQTT.async_open(broker, session_expiry_interval: 0xFFFFFFFF)
```
