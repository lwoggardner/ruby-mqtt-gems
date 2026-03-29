# Project Context: async-mqtt

## Test Framework
- Uses **Minitest**
- Run tests: `bundle exec rake test` or individual files with `bundle exec ruby spec/file_spec.rb`
- Multiple files: `bundle exec ruby -r ./spec/file1.rb -r ./spec/file2.rb -e 'Minitest.run'`
- Sequential tests: `bundle exec rake test:sequential test` — disables parallelization, useful when debugging hangs
- Debug logging: `DEBUG=1 bundle exec ruby spec/file_spec.rb` — for individual tests only, before adding puts statements
- Filter skipped tests from output: pipe through `sed '/^Skipped:/,/^$/d'`
  - e.g. `bundle exec rake test:sequential test 2>&1 | sed '/^Skipped:/,/^$/d'`
  - Skipped tests are expected and should not consume tokens in AI context

## Project Structure
- Multi-gem repository (monorepo)
- Gems:
  - `mqtt-core` - Core MQTT client implementation
  - `mqtt-v3` - MQTT 3.1.1 protocol
  - `mqtt-v5` - MQTT 5.0 protocol with JSON-RPC support
  - `json_rpc_kit` - Transport-agnostic JSON-RPC toolkit
  - `concurrent_monitor` - Unified concurrency abstraction (Thread/Fiber)

## Key Patterns
- Uses Ruby 3.4+ features (Data.define, pattern matching)
- Supports both threaded and async (fiber-based) execution models
- Immutable packet structures
- LSP support enabled for code navigation
