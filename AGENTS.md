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

### Linting
- `rake lint` — runs rubocop + yard:check (no doc generation)
- `rake yard` — generates full YARD documentation

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

## Release Process

### Version Management
- All gem versions are kept in sync via `VERSION_FILES` in the Rakefile
  - `gems/mqtt-core/lib/mqtt/version.rb` (shared by mqtt-core, mqtt-v3, mqtt-v5)
  - `gems/concurrent_monitor/lib/concurrent_monitor/version.rb`
  - `gems/json_rpc_kit/lib/json_rpc_kit/version.rb`
- `rake version:show` — display current versions and branch
- `rake version:bump_minor` — bump minor version across all gems

### Pre-release
- Work on a release branch (e.g. `release/0.9`)
- `rake version:tag_prerelease[rc1]` — creates tag `v{VERSION}.rc1`
- Without suffix argument, falls back to branch-name-derived suffix
- Push branch and tag: `git push && git push --tags`

### Final Release
- Merge release branch to `main`
- `rake version:tag` — creates tag `v{VERSION}` (must be on `main`)
- Push: `git push && git push --tags`

### CI/CD
- Tag pushes matching `v[0-9]+.[0-9]+.[0-9]+*` trigger the release workflow
- The `release` GitHub environment requires manual approval before gems are published
- Release order (dependency chain): concurrent_monitor → mqtt-core → json_rpc_kit → mqtt-v3 → mqtt-v5
- The release workflow does not use bundler — it runs `gem build` + `gem push` directly