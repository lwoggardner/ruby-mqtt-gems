# frozen_string_literal: true

require_relative 'client/client_id_generator'
require_relative 'client/enumerable_subscription'
require_relative 'client/socket_factory'
require_relative 'client/connection'
require_relative 'client/session'
require_relative 'client/acknowledgement'
require_relative 'client/retry_strategy'
require_relative '../logger'
require_relative '../errors'
require 'forwardable'
require 'concurrent_monitor'

module MQTT
  module Core
    # rubocop:disable Metrics/ClassLength

    # MQTT Client
    #
    # @note In this documentation, "thread" refers to a {ConcurrentMonitor::Task}, which may be implemented
    #   as either a Thread (default) or a Fiber (when using async variants).
    #
    # @abstract use a specific MQTT protocol version subclass.
    # @see MQTT.open
    class Client
      extend ClientIdGenerator

      class << self
        #   Open an MQTT client connection
        #
        #   If a block is provided the client is yielded to the block and disconnection is ensured, otherwise
        #   the client is returned directly.
        # @overload open(*io_args, session_store:, **configure)
        #   @param [Array] io_args see {SocketFactory}
        #   @param [SessionStore] session_store  MQTT session store for unacknowledged QOS1/QOS2 packets
        #     see {memory_store} or {file_store}
        #   @param [Hash] configure data for {#configure}
        #   @return [Client] (if a block is not given)
        #   @yield [client]
        #   @yieldparam [Client] client
        #   @yieldreturn [void]
        # @see MQTT.open
        def open(*io_args, monitor: mqtt_monitor, session_store: memory_store, **configure)
          socket_factory = SocketFactory.create(*io_args, options: configure)
          new_opts = { socket_factory:, monitor:, session_store:, **new_options(configure) }
          client = new(**new_opts).tap { |c| c.configure(**configure) }

          return client unless block_given?

          client.sync do
            yield client
            client.disconnect
          rescue StandardError => e
            client.disconnect(cause: e)
            raise
          end
        end

        # @!group Configuration Factories

        # A session store that only allows messages with QoS 0
        # @return [Qos0SessionStore]
        def qos0_store(...)
          require_relative 'client/qos0_session_store'
          Qos0SessionStore.new(...)
        end

        # An in-memory session store. Can recover from network interruptions but not a crash of the client.
        # @return [MemorySessionStore]
        def memory_store(...)
          require_relative 'client/memory_session_store'
          MemorySessionStore.new(...)
        end

        # A filesystem based session store. Can recover safely from network interruptions and process restarts
        # @return [FilesystemSessionStore]
        def file_store(...)
          require_relative 'client/filesystem_session_store'
          FilesystemSessionStore.new(...)
        end

        # Construct a retry strategy for automatic reconnection
        # @return [RetryStrategy]
        def retry_strategy(...)
          RetryStrategy.new(...)
        end

        # @!endgroup

        # @!visibility private
        def thread_monitor = ConcurrentMonitor.thread_monitor

        # @!visibility private
        def async_monitor = ConcurrentMonitor.async_monitor

        # @!visibility private
        # the default concurrent_monitor uses Threads for concurrency
        def mqtt_monitor = thread_monitor

        # @!visibility private
        def create_session(*io_args, **session_args)
          self::Session.new(*io_args, **session_args)
        end

        # @!visibility private
        def create_connection(**connection_args)
          self::Connection.new(**connection_args)
        end

        # @!visibility private
        # Extract and remove options for new - subclasses can override to add more
        def new_options(_opts)
          {}
        end
      end

      extend Forwardable
      include Logger

      # @!visibility private
      include ConcurrentMonitor

      # @!attribute [r] uri
      #   @return [URI] universal resource indicator derived from io_args passed to {MQTT.open}
      def_delegator :socket_factory, :uri

      # @return [String] client_id and connection status
      def to_s
        "#{self.class.name}:#{uri} client_id=#{client_id}, status=#{status}"
      end

      def_delegators :connection, :keep_alive, :connected?

      def_delegators :session, :client_id, :expiry_interval, :max_qos

      # @!visibility private
      def initialize(socket_factory:, monitor:, session_store:)
        @socket_factory = socket_factory
        @session = self.class.create_session(client: self, monitor:, session_store:)
        monitor_extended(monitor.new_monitor)
        @status = :configure
        @acks = {}
        @subs = Set.new
        @unsubs = Set.new
        @run_args = {}
        @events = {}
      end

      # Configure client connection behaviour
      # @param [Hash<Symbol>] connect options controlling connection and retry behaviour.
      #   Options not explicitly specified below are passed to the `CONNECT` packet
      # @option connect [RetryStrategy,true] retry_strategy See {configure_retry}
      # @raise [Error] if called after a connection has left the initial `:configure` state
      # @return [self]
      def configure(**connect)
        synchronize { raise Error, "Can't configure with status: #{@status}" unless @status == :configure }

        configure_retry(connect.delete(:retry_strategy)) if connect.key?(:retry_strategy)

        @run_args.merge!(connect)
        self
      end

      # Register a retry strategy as the disconnect handler
      # @overload configure_retry(**retry_args)
      #   @param [Hash<Symbol>] retry_args sugar to construct a {RetryStrategy}
      # @overload configure_retry(retry_strategy)
      #   @param [RetryStrategy|:retry!|Hash|Boolean] retry_strategy
      #     - true: default RetryStrategy
      #     - Hash: RetryStrategy.new(**hash)
      #     - RetryStrategy or has #retry!: use as-is
      #     - false/nil: no retries
      # @return [self]
      # @see on_disconnect
      def configure_retry(*retry_strategy, **retry_args)
        retry_strategy = retry_strategy.empty? ? RetryStrategy.new(**retry_args) : retry_strategy.first
        retry_strategy = RetryStrategy.new if retry_strategy == true
        retry_strategy = RetryStrategy.new(**retry_strategy) if retry_strategy.is_a?(Hash)
        if retry_strategy
          raise ArgumentError, "Invalid retry strategy: #{retry_strategy}" unless retry_strategy.respond_to?(:retry!)

          on(:disconnect) { |retry_count, &raiser| retry_strategy.retry!(retry_count, &raiser) }
        else
          on(:disconnect) { |_c, &r| r&.call }
        end
        self
      end

      # @!group Event Handlers

      # @!method on_birth(&block)
      # Birth Handler: Block is executed asynchronously after the first successful connection for a session.
      #
      # Typically used to establish {EnumerableSubscription#async} handlers that process received messages for the
      # duration of a Session.
      #
      # @note Prior to the completion of this event, received QoS 1/2 messages are retained in memory and matched for
      #      delivery against new {#subscribe} requests.
      # @yield
      # @yieldreturn [void]
      # @return [self]

      # Connect Handler
      # @!method on_connect(&block)
      #   Called each time the client is successfully (re)connected to a broker
      #   @yield [connect, connack]
      #   @yieldparam [Packet] connect the `CONNECT` packet sent by this client
      #   @yieldparam [Packet] connack the `CONNACK` packet received from the server
      #   @yieldreturn [void]
      #   @return [self]

      # @!method on_disconnect(&block)
      #   Called each time the client is disconnected from a broker.
      #
      #   The default handler calls raiser without rescuing any errors and thus prevents the client
      #   from reconnecting.
      #
      #   {#configure_retry} can be used to register a {RetryStrategy} which rescues retriable protocol and networking
      #   errors and uses exponential backoff before allowing reconnection.
      #
      #   Installing a custom handler that does not re-raise errors will cause the client to retry connections forever.
      #
      #   @yield [retry_count, &raiser]
      #   @yieldparam [Integer] retry_count number of retry attempts since the last successful connection
      #   @yieldparam [Proc] raiser callable will raise the error (if any) that caused the connection to be closed,
      #   @yieldreturn [void]
      #   @return [self]

      # @!method on_publish(&block)
      #   Called on {#publish}
      #   @yield [publish, ack]
      #   @yieldparam [Packet] publish the `PUBLISH` packet sent by this client
      #   @yieldparam [Packet|nil] ack qos 0: nil, qos 1: `PUBACK`, qos 2: `PUBCOMP`
      #   @yieldreturn [void]
      #   @return [self]

      # @!method on_subscribe(&block)
      #   Called on {#subscribe}
      #   @yield [subscribe, suback]
      #   @yieldparam [Packet] subscribe the `SUBSCRIBE` packet sent by this client
      #   @yieldparam [Packet] suback the `SUBACK` packet received from the server
      #   @yieldreturn [void]
      #   @return [self]

      # @!method on_unsubscribe(&block)
      #   Called on {#unsubscribe}
      #   @yield [unsubscribe, unsuback]
      #   @yieldparam [Packet] unsubscribe the `UNSUBSCRIBE` packet sent by this client
      #   @yieldparam [Packet] unsuback the `UNSUBACK` packet received from the server
      #   @yieldreturn [void]
      #   @return [self]

      # @!method on_send(&block)
      #   Called before a packet is sent
      #   @yield [packet]
      #   @yieldparam [Packet] packet
      #   @yieldreturn [void]
      #   @return [self]

      # @!method on_receive(&block)
      #   Called when a packet is received
      #   @yield [packet]
      #   @yieldparam [Packet] packet
      #   @yieldreturn [void]
      #   @return [self]

      %i[birth connect disconnect publish subscribe unsubscribe send receive].each do |event|
        define_method "on_#{event}" do |&block|
          on(event, &block)
        end
      end

      # @!endgroup

      # @return [Symbol] the current status of the client
      attr_reader :status

      # Start the MQTT connection
      # @param [Hash<Symbol>] connect additional options for the `CONNECT` packet.
      #   Client must still be in the initial `:configure` state to pass options
      # @return [self]
      def connect(**connect)
        configure(**connect) unless connect.empty?
        connection
        self
      end

      # Disconnect cleanly and stop the client
      #
      # Once called, no further calls can be made on the client.
      #
      # @param [Exception|nil] cause Used to set error information in the `DISCONNECT` packet
      # @param [Hash<Symbol>] disconnect Additional properties for the `DISCONNECT` packet
      # @return [self] with state `:stopped`
      def disconnect(cause: nil, **disconnect)
        synchronize do
          @status = :stopped if @status == :configure
          @stopping ||= current_task
        end

        # At this point only the original disconnect thread can use the connection
        cleanup_connection(cause, **disconnect) if @stopping == current_task && @status != :stopped
        @run&.wait
        self
      ensure
        stop!
      end

      # @overload publish(topic_name, payload, retain: false, qos: 0, timeout: 0, **publish)
      #   @param [String<UTF8>> topic_name UTF8 encoded topic name
      #   @param [String<Binary>] payload the message payload
      #   @param [Boolean] retain true if the message should be retained
      #   @param [Integer] qos the Quality of Service level (0, 1 or 2)
      #   @param [Hash<Symbol>] **publish additional properties for the `PUBLISH` packet (version-dependent)
      #   @return [self]
      #   @see on_publish
      def publish(*pub_args, **publish)
        topic_name, payload = pub_args
        publish[:topic_name] = topic_name if topic_name
        publish[:payload] = payload if payload
        connection.publish(**publish) { |pub| send_and_wait(pub) { |ack| handle_ack(pub, ack) } }
        self
      end

      # Subscribe to topics
      #
      # @overload subscribe(*topic_filters,**subscribe)
      #   Subscribe and return an {EnumerableSubscription} for enumeration.
      #
      #   The returned {EnumerableSubscription} holds received and matching messages in an internal
      #   queue which can be enumerated over using {EnumerableSubscription#each} or {EnumerableSubscription#async}
      #
      #   @param [Array<String<UTF8>|Hash>] topic_filters List of filter expressions. Each element can be
      #     a String or a Hash with `:topic_filter` and `:max_qos` keys.
      #   @param [Hash<Symbol>] **subscribe additional properties for the `SUBSCRIBE` packet (version-dependent)
      #   @option subscribe [Integer] max_qos default maximum QoS to request for each topic_filter
      #   @return [EnumerableSubscription]
      #   @raise [SubscriptionError] if the server rejects any topic filters
      #   @example Wait for and return the first message
      #     topic, message = client.subscribe('some/topic').first
      #   @example Using enumerator from {EnumerableSubscription#each}
      #     client.subscribe('some/topic').each { |topic,msg| process(topic,msg) or break }
      #   @example Enumerating in a new thread via {EnumerableSubscription#async}
      #     client.subscribe('some/topic#').async { |topic, msg| process(topic, msg) }
      #   @example With different QoS levels per topic filter
      #     client.subscribe('status/#', { topic_filter: 'data/#', max_qos: 2 }, max_qos: 1)
      #
      # @overload subscribe(*topic_filters, **subscribe, &handler)
      #   Subscribe with a block handler for direct packet processing
      #
      #   @param [Array<String<UTF8>|Hash>] topic_filters List of filter expressions
      #   @param [Hash<Symbol>] **subscribe additional properties for the `SUBSCRIBE` packet (version-dependent)
      #   @option subscribe [Integer] max_qos default maximum QoS to request for each topic_filter
      #   @yield [packet] Block is called directly from the receive thread for each matching packet
      #   @yieldparam [Packet<PUBLISH>|nil] packet the received `PUBLISH` packet, or nil on disconnect
      #   @yieldreturn [void]
      #   @return [Subscription]
      #   @raise [SubscriptionError] if the server rejects any topic filters
      #
      #   @note WARNING: This block is executed synchronously on the IO thread that is receiving packets.
      #     Any blocking operations will prevent other packets from being received, causing timeouts
      #     and eventual disconnection.
      #
      #   @example Direct packet processing (use with caution)
      #     sub = client.subscribe('some/topic') { |pkt| puts pkt.payload if pkt }
      #     # ...
      #     sub.unsubscribe
      #
      # @see Subscription
      # @see on_subscribe
      def subscribe(*topic_filters, **subscribe, &handler)
        handler ||= new_queue
        topic_filters += subscribe.delete(:topic_filters) || []
        connection.subscribe(topic_filters:, **subscribe) do |sub_pkt|
          send_and_wait(sub_pkt) do |suback_pkt|
            handle_ack(sub_pkt, suback_pkt)
            new_subscription(sub_pkt, suback_pkt, handler).tap { |sub| qos_subscription(sub) }
          end
        end
      rescue SubscribeError
        unsubscribe(*topic_filters)
        raise
      end

      # Safely unsubscribe inactive topic filters
      #
      # @param [Array<String>] topic_filters list of filters
      # @param [Hash<Symbol>] unsubscribe additional properties for the `UNSUBSCRIBE` packet
      # @return [self]
      # @note Topic filters that are in use by active Subscriptions are removed from the `UNSUBSCRIBE` request.
      # @see Subscription#unsubscribe
      # @see #on_unsubscribe
      def unsubscribe(*topic_filters, **unsubscribe)
        topic_filters += unsubscribe.delete(:topic_filters) || []

        synchronize do
          topic_filters -= (@subs - @unsubs).flat_map(&:subscribed_topic_filters)
          return [] unless topic_filters.any?

          connection.unsubscribe(topic_filters:, **unsubscribe) do |unsub_pkt|
            send_and_wait(unsub_pkt) { |unsuback_pkt| handle_ack(unsub_pkt, unsuback_pkt) }
          end
        end
        self
      end

      # @!visibility private
      # Called by Subscription#unsubscribe.
      def delete_subscription(subscription, **unsubscribe_params)
        synchronize do
          @unsubs.add(subscription)
          unsubscribe(**unsubscribe_params).tap do
            @unsubs.delete(subscription)
            @subs.delete(subscription)
          end
        end
        subscription.put(nil)
      end

      # @!visibility private
      # @return [Boolean] true if this subscription is active - will receive a final 'put'
      def active_subscription?(subscription)
        synchronize { @subs.include?(subscription) }
      end

      # @!visibility private
      # Called by self to enqueue packets from client threads,
      #   or by receive thread to enqueue packets related to protocol flow
      def push_packet(*packets)
        synchronize { send_queue.push(*packets) }
      end

      # @!visibility private
      # Called by: Connection's receive thread for received ACK type packets
      def receive_ack(packet)
        synchronize { acks.delete(packet.id)&.fulfill(packet) }
      end

      # @!visibility private
      # Called by: Connection receive loop for received `PUBLISH` packets
      # @return [Array<Subscription>] matched subscriptions
      def receive_publish(packet)
        synchronize do
          subs.select { |s| s.match?(packet) } # rubocop:disable Style/SelectByRegexp
        end
      end

      # @!visibility private
      # Called by: {Connection} receive_loop when it reaches io end of stream
      def receive_eof
        push_packet(:eof)
      end

      # @!visibility private
      def packet_module
        self.class.packet_module
      end

      # @!visibility private
      def handle_event(event, *, **kw_args, &)
        events[event]&.call(*, **kw_args, &)
      end

      # @!visibility private
      def_delegators :packet_module, :build_packet, :deserialize

      # @!visibility private
      # session methods called via Subscription
      def_delegators :session, :handled!

      private

      attr_reader :events, :session, :send_queue, :monitor, :socket_factory, :conn_cond, :subs, :acks, :conn_count

      def monitor_extended(monitor)
        @monitor = monitor
        @send_queue = new_queue
        @conn_cond = new_condition
      end

      def on(event, &handler)
        synchronize do
          raise ArgumentError, 'Configuration must be called before first packet is sent' if events.frozen?

          events[event] = handler
        end
        self
      end

      # This is used for the API methods to obtain an active connection
      # It starts the connect loops if necessary and blocks until a connection is available
      def connection
        synchronize do
          run if @status == :configure
          conn_cond.wait_while { @status == :disconnected }
          raise ConnectionError, 'Stopped.', cause: @exception if @status == :stopped && @exception
          raise ConnectionError, "Not connected. #{@status}" unless @status == :connected
          raise ConnectionError, 'Disconnecting...' if @stopping && @stopping != current_task

          @connection
        end
      end

      def new_connection
        log.info { "Connecting to #{uri}" }
        io = socket_factory.new_io
        self.class.create_connection(client: self, session:, io:, monitor:)
      end

      def run
        return unless @status == :configure

        configure_defaults
        @status = :disconnected
        # don't allow any more on_ events.
        events.freeze
        @run ||= async(:run) { safe_run_task }
      end

      def configure_defaults
        configure_default_retry unless @events[:disconnect]
      end

      def configure_default_retry
        log.warn <<~WARNING if session.max_qos.positive?
          No automatic retry strategy has been configured for this MQTT client.

          This is not recommended for applications using QoS levels 1 or 2, as message
          delivery guarantees may be compromised during network interruptions.

          To suppress this warning use #configure_retry to explicitly configure or disable the retry strategy.
          Alternatively use the #qos0_store to limit PUBLISH and SUBSCRIBE to QoS 0.
        WARNING
        configure_retry(false)
      end

      def run_task(retry_count: 0)
        # no point trying to connect if the session is already expired
        session.expired!
        run_connection(**@run_args) { retry_count = 0 }
        disconnected!(0) { nil }
      rescue StandardError => e
        disconnected!(retry_count += 1) { raise e }
        # If we are going to restart with a clean session existing acks and subs need to be cancelled.
        retry unless synchronize do
          @stopping.tap { |stopping| cancel_session('Restarting session', e) if !stopping && session.clean? }
        end
      ensure
        stop!(e)
      end

      def safe_run_task
        run_task
      rescue StandardError => e
        log.error(e)
      end

      def run_connection(**connect_data)
        conn = establish_connection(**connect_data)
        yield if block_given?
        with_barrier do |b|
          b.async(:send_loop) { send_loop(conn) }
          b.async(:recv_loop) { receive_loop(conn) }
          b.wait!
        ensure
          conn.close
        end
      end

      def establish_connection(**connect)
        # Socket factory URI can contain username, password
        connect.merge!(socket_factory.auth) if socket_factory.respond_to?(:auth)

        new_connection.tap do |conn|
          connect_packet, connack_packet = conn.connect(**connect)
          synchronize { connected!(conn, connect_packet, connack_packet) }
          birth! unless session.birth_complete?
        end
      end

      def birth!
        async(:birth) do
          handle_event(:birth)
          session.birth_complete!
        rescue ConnectionError => e
          log.warn { "Ignoring ConnectionError in birth handler: #{e.class}: #{e.message}" }
        rescue StandardError => e
          log.error { "Unexpected error in birth handler: #{e.class}: #{e.message}. Disconnecting..." }
          disconnect(cause: e)
        end
      end

      # @note synchronized - sub needs to be available to immediate receive publish
      def new_subscription(sub_packet, ack_packet, handler)
        # noinspection RubyArgCount
        klass = handler.respond_to?(:call) ? Subscription : EnumerableSubscription
        klass.new(sub_packet, ack_packet, handler || new_queue, self).tap { |sub| @subs.add(sub) }
      end

      def qos_subscription(sub)
        return unless sub.sub_packet.max_qos.positive?

        # When re-establishing a subscription to a live session, there may be matching messages already received
        session.qos_subscribed { |p| sub.match?(p) }.each { |p| sub.put(p) }
      end

      def connected!(conn, connect_pkt, connack_pkt)
        session.connected!(connect_pkt, connack_pkt)
        handle_event(:connect, connect_pkt, connack_pkt)
        send_queue.push(*session.retry_packets)
        @connection = conn
        @status = :connected
        conn_cond.broadcast
      end

      # @!visibility private
      # @param [Connection] connection as yielded from {#run}
      def send_loop(connection, keep_alive_factor: 0.7)
        connection.send_loop { |keep_alive| next_packet(send_timeout(keep_alive, keep_alive_factor)) }
      end

      # @!visibility private
      # @param [Connection] connection as yielded from {#run}
      def receive_loop(connection)
        connection.receive_loop
      end

      def send_timeout(keep_alive, factor)
        return nil unless keep_alive&.positive?

        keep_alive * factor
      end

      def disconnected!(retry_count, &)
        synchronize { @status = :disconnected if @status == :connected }
        session.disconnected!
        handle_event(:disconnect, retry_count, &)
      end

      def next_packet(keep_alive_timeout = nil)
        synchronize { send_queue.shift(keep_alive_timeout) }
      end

      def handle_ack(pkt, ack)
        handle_event(pkt.packet_name, pkt, ack)
        pkt.success!(ack)
      end

      def send_and_wait(packet, &)
        synchronize do
          ack = acks[packet.id] = Acknowledgement.new(packet, monitor:, &) if packet.id

          send_queue.push(packet)

          ack&.value || yield(nil)
        end
      end

      def cleanup_connection(cause, **disconnect)
        # wait for acks
        acks.each_value(&:wait) if cause

        connection.disconnect(cause, **disconnect) { |disconnect_packet| send_queue.push(disconnect_packet) }
      end

      def stop!(exception = nil)
        return if @status == :stopped

        synchronize do
          next if @status == :stopped

          @exception = exception
          @status = :stopped
          cancel_session('Connection stopped', exception)
          conn_cond.broadcast
          @run&.stop unless @run&.current?
        end
      end

      # called before retrying with a clean session or while stopping?
      def cancel_session(msg, cause = nil)
        conn_error = ConnectionError.new(msg)
        cancel_acks(conn_error)
        # Send nil on clean disconnect, ConnectionError on error disconnect
        cancel_subs(cause ? conn_error : nil)
      end

      def cancel_subs(cause)
        subs.each { |sub| sub.put(cause) }
        subs.clear
      end

      def cancel_acks(cause)
        acks.each_value { |a| a.cancel(cause) }
      end
    end

    # rubocop:enable Metrics/ClassLength
  end
end
