# frozen_string_literal: true

require_relative 'core/client'
require_relative 'options'

# MQTT top level namespace
module MQTT
  class << self
    include Options

    # Construct and Configure an MQTT client
    #
    # If a block is provided, yields the client and ensures disconnection.
    # Otherwise, the client is returned directly.
    #
    # In either case the client is provided in `:configure` state and not yet connected to the broker.
    #
    # @note All scalar-valued options (String, Integer, Float, Boolean) can be provided as URI query parameters
    #   unless `ignore_uri_params: true` is set. URI parameters override explicit keyword arguments.
    #
    # @overload open(*io_args, **client_opts)
    #   @param io_args see {Core::Client::SocketFactory}. Typically an `mqtt[s]://` or `unix://` URI
    #   @param [Hash<Symbol>] client_opts
    #   @option client_opts [Boolean] ignore_uri_params (false)
    #     When true, URI query parameters are ignored. Use where URI input is untrusted.
    #   @option client_opts [Hash<Symbol>] **socket_factory options passed to {Core::Client::SocketFactory}
    #
    #      - `host`, `port`, `local_addr`, `local_port`, `scheme`, `connect_timeout`, `ssl_(.*)`
    #   @option client_opts [Hash<Symbol>] **logger options passed to {MQTT::Logger.configure}
    #
    #      - `log_(.*)`
    #   @option client_opts [Integer] protocol_version ([5, 3]) MQTT protocol major version
    #
    #     - 5 requires `mqtt/v5` gem
    #     - 3 requires `mqtt/v3` gem.
    #     - If not set, v5 is preferred over v3 based on the ability to load the requisite gem.
    #   @option client_opts [String, nil] client_id ('') Session identifier
    #
    #     - Default empty string implies anonymous or server-assigned ids
    #     - Set to nil to force generation of a random id if the broker does not support anonymous ids
    #     - {Core::Client::FilesystemSessionStore} requires a fixed, non-empty client_id
    #   @option client_opts [Integer, nil] session_expiry_interval Duration in seconds before the session
    #     expires after disconnect
    #
    #     - Set to nil to use maximum (130+ years) expiry
    #   @option client_opts [String, Pathname] session_base_dir Base directory for
    #     {Core::Client::FilesystemSessionStore}
    #   @option client_opts [Core::Client::SessionStore, Class, Proc] session_store SessionStore instance, Class,
    #     or factory
    #
    #     - Class/Proc is called with `client_id` and `session_(.*)` options
    #     - If not set
    #        - with `:session_base_dir` a {Core::Client::FilesystemSessionStore} is constructed
    #        - with `:session_expiry_interval` a {Core::Client::MemorySessionStore} is constructed
    #        - defaults to constructing a {Core::Client::Qos0SessionStore}
    #
    #   @option client_opts [Core::Client::RetryStrategy, Class, Proc, Boolean] retry_strategy RetryStrategy instance,
    #     Class, or factory. Determines how to retry after connection dropouts.
    #
    #     - Class/Proc is called with other `retry_(.*)` options
    #     - Explicitly false or nil disables retries
    #     - If not set
    #        - If other `retry_(.*)` options are present, they are used to construct a {Core::Client::RetryStrategy}
    #        - If the `:session_store` option resolves to only support QoS0, then retries are disabled
    #        - Otherwise, a {Core::Client::RetryStrategy} is constructed with default settings
    #   @option client_opts [Integer] keep_alive (60)
    #     Duration in seconds between PING packets sent to the broker to keep the connection alive.
    #   @option client_opts [Hash<Symbol>] **topic_alias options to build a {V5::TopicAlias::Manager} (V5 only)
    #
    #     - `topic_aliases` TopicAlias::Manager instance, Class, or factory. (default {V5::TopicAlias::Manager})
    #     - `policy` TopicAlias::Policy instance, Class, or factory. (default {V5::TopicAlias::LRUPolicy})
    #     - `send_maximum` Integer maximum number of topic aliases to send to the broker.
    #           Default is the broker limit if a policy is set, otherwise 0, effectively disabling outgoing topic
    #           aliases.
    #
    #   @option client_opts [Hash<Symbol>] **connect other CONNECT packet options
    #   @yield [client] Yields the configured client for use within the block
    #   @yieldparam client [Core::Client] the MQTT client instance {V5::Client} or {V3::Client}
    #   @return [Core::Client] the client if no block is given
    #   @return [void] if a block is given
    #   @raise [LoadError] if no suitable MQTT gem can be found
    # @example Default usage - entirely configured via URI from environment variable
    #   # ENV['MQTT_SERVER'] => 'mqtt://localhost'
    #   MQTT.open do |client|
    #     client.connect(will_topic: 'status', will_payload: 'offline')
    #     client.publish(topic, payload)
    #   end
    # @example Untrusted URI input, only directly set options are used
    #   MQTT.open(untrusted_uri, ignore_uri_params: true, ssl_min_version: :TLSv1_2) do |client|
    #     client.connect
    #     #...
    #   end
    # @example Force v5 protocol
    #   MQTT.open(mqtt_uri, protocol_version: 5) do |client|
    #     client.connect
    #     # ...
    #   end
    # @example Need Qos1/2 guarantees only as long as the process is running
    #   MQTT.open(mqtt_uri, session_expiry_interval: nil) do |client|
    #     client.session_store # => Core::Client::MemorySessionStore
    #     client.publish(topic, payload, qos: 2)
    #     # ...
    #   end
    # @example Full Qos1/2 guarantees including over process restarts within one day
    #   mqtt_uri = "mqtt://host.example.com/?client_id=#{ENV['HOSTNAME']}"
    #   MQTT.open(mqtt_uri, session_base_dir: '/data/mqtt', session_expiry_interval: 86400) do |client|
    #     client.session_store # => Core::Client::FilesystemSessionStore
    #     client.on_birth do
    #       client.subscribe(*topics, max_qos: 2).async { |topic, payload| process(topic, payload) }
    #     end
    #     sleep # until process terminates
    #   end
    #
    def open(*io_args, async: false, **client_opts, &)
      # SocketFactory will claim its keyword options, client_opts is left with the remaining options
      sf = Core::Client::SocketFactory.create(*io_args, options: client_opts)
      client_opts.merge!(sf.query_params) if sf.respond_to?(:query_params)
      MQTT::Logger.configure(**slice_opts!(client_opts, prefix: 'log_'))

      class_opts = { async: async, protocol_version: client_opts.delete(:protocol_version) || %w[5 3] }
      client_class = client_class(**class_opts)

      session_store = session_store(
        **slice_opts!(client_opts, :client_id, :session_store, prefix: 'session_')
      )

      open_opts = {
        **retry_strategy(max_qos: session_store.max_qos, **slice_opts!(client_opts, :retry_strategy, prefix: 'retry_')),
        **slice_opts!(client_opts, :keep_alive)
      }

      v5_specific_options(client_class.protocol_version, client_opts, open_opts)

      client_class.open(sf, session_store:, **client_opts, **open_opts, &)
    end

    # Utility to test broker connectivity
    #
    # Connect to the broker, outputting status information
    # @see open
    def test(*io_args, **client_opts)
      self.open(*io_args, **client_opts) do |client|
        client.configure_retry(false)
        puts "Client: #{client}"
        puts "   Session: #{client.session_store}"
        client.connect
        puts "   Status: #{client.status}"
      end
    end

    # As per {open} but returns an Async client that uses Fibers for concurrency
    #
    # If not using the block form, {Core::Client#connect} and later methods must be called within the reactor.
    # @example Async client usage
    #   require 'async'
    #   require 'mqtt/core'
    #
    #   client = MQTT.async_open('localhost')
    #   Sync do
    #     client.connect
    #     client.publish(topic, payload)
    #   end
    # @yield [client] Yields the configured client for use within the block
    # @yieldparam client [Core::Client] the MQTT client instance {V5::Async::Client} or {V3::Async::Client}
    # @return [Core::Client] the client if no block is given
    # @return [void] if a block is given
    def async_open(*io_args, **client_opts, &)
      self.open(*io_args, async: true, **client_opts, &)
    end

    private

    def client_class(protocol_version:, async:)
      protocol_version = [protocol_version] unless protocol_version.is_a?(Array)
      protocol_version.map(&:to_s).each do |v|
        raise ArgumentError, "Invalid mqtt-version #{v}" unless %w[3 5 31 3.1 50 5.0 3.1.1 311].include?(v)

        v = v[0]
        require async ? "mqtt/v#{v}/async/client" : "mqtt/v#{v}"
        return Class.const_get("MQTT::V#{v}::#{'Async::' if async}Client")
      rescue LoadError => _e
        # warn e
      end
      raise LoadError, "Could not find MQTT gem for protocol versions: #{protocol_version}"
    end

    def session_store(session_store: nil, **opts)
      return construct(session_store, **opts) if session_store

      return Core::Client.file_store(**opts) if opts.key?(:base_dir)
      return Core::Client.memory_store(**opts) if opts.key?(:expiry_interval)

      Core::Client.qos0_store(**opts)
    end

    # @return [RetryStrategy] URI parameters (prefixed 'retry_') override provided defaults
    # @see open
    def retry_strategy(max_qos:, retry_strategy: max_qos.positive? || :__not_set__, **options)
      return {} if retry_strategy == :__not_set__ && options.empty?
      return { retry_strategy: false } if %w[false 0 no n nil].include?(retry_strategy.to_s.downcase) && options.empty?
      return { retry_strategy: construct(retry_strategy, **options) } if retry_strategy

      { retry_strategy: Core::Client.retry_strategy(**options) }
    end

    # extract from client_opts into open_opts
    def v5_specific_options(protocol_version, client_opts, open_opts)
      v5_opts(
        protocol_version, client_opts, open_opts,
        :topic_aliases, :topic_alias_maximum, prefix: 'topic_alias_'
      ) { |**ta_opts| topic_alias_opts(**ta_opts) }
    end

    def v5_opts(protocol_version, client_opts, open_opts, *slice_keys, prefix: nil, &block)
      if protocol_version == 5
        v5_opts = slice_opts!(client_opts, *slice_keys, prefix:)
        open_opts.merge!(block.call(**v5_opts))
      else
        MQTT::Logger.log.warn "Ignoring #{prefix}* options for protocol version #{protocol_version}"
      end
    end

    def topic_alias_opts(
      topic_aliases: V5::TopicAlias::Manager, topic_alias_maximum: nil,
      policy: nil, send_maximum: :__not_set__, **
    )
      # Use broker limit if we have a policy but no send limit
      send_maximum = nil if send_maximum == :__not_set__
      send_maximum = coerce_integer(send_maximum:) if send_maximum

      policy = construct(policy, **)
      topic_aliases = construct(topic_aliases, policy:, send_maximum:, **)

      { topic_aliases: topic_aliases, topic_alias_maximum: }.compact
    end
  end
end
