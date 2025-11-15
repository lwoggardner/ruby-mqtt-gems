# Local Mosquitto Test Broker

This directory contains configuration for a local mosquitto broker that mimics test.mosquitto.org for testing.

## Setup

1. Generate SSL certificates:
   ```bash
   ./generate_certs.sh
   ```

2. Start the broker:
   ```bash
   docker-compose --profile stable up -d
   ```

3. Generate password file (if needed):
   ```bash
   docker exec async-mqtt-test-broker mosquitto_passwd -c /mosquitto/config/passwd ro
   # Enter password: readonly
   ```

## Listeners

The local broker provides these listeners matching test.mosquitto.org:

- **1883**: MQTT, anonymous
- **1884**: MQTT, password auth (user: ro, password: readonly)
- **8883**: MQTTS with custom certificate
- **8884**: MQTTS with client certificate required
- **8885**: MQTTS with password auth
- **8886**: MQTTS with default CA bundle certificate
- **8887**: MQTTS with expired certificate (for testing errors)
- **Unix socket**: /mosquitto/sockets/mqtt.sock

## Running Tests

Run against local broker (default):
```bash
bundle exec ruby spec/connection_spec.rb
```

Run against test.mosquitto.org:
```bash
TEST_BROKER=test.mosquitto.org bundle exec ruby spec/connection_spec.rb
```

## Notes

- The Unix socket test only runs when the socket file exists
- The default CA bundle test (port 8886) only runs against test.mosquitto.org
- Port 8885 (authenticated SSL) is currently broken on test.mosquitto.org and skipped
- Docker Compose profile 'testing' runs 2.0.99 (2.1 beta) with server side topic alias support.