# frozen_string_literal: true

require 'uri'

module URI
  # MQTT over TCP
  # @see https://github.com/mqtt/mqtt.github.io/wiki/URI-Scheme
  class MQTT < ::URI::Generic
    DEFAULT_PORT = 1883

    # Options for MQTT URI new_io method
    IO_OPTS = %i[connect_timeout resolv_timeout tcp_nodelay].freeze

    def require_deps
      require 'socket'
    end

    # Create a TCP socket connection to the MQTT broker
    # @param local_args [Array] Optional local_host and local_port for binding
    # @param connect_timeout [Numeric, nil] Timeout in seconds for connection establishment
    # @param resolv_timeout [Numeric, nil] Timeout in seconds for DNS resolution (defaults to connect_timeout)
    # @param tcp_nodelay [Boolean] Enable TCP_NODELAY to avoid waiting to coalesce packets (default: true)
    # @return [TCPSocket]
    def to_io(*local_args, connect_timeout: nil, resolv_timeout: connect_timeout, tcp_nodelay: true)
      TCPSocket.new(host, port, *local_args, connect_timeout:, resolv_timeout:).tap do |socket|
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) if tcp_nodelay
        socket.timeout = connect_timeout if connect_timeout
      end
    end
  end

  # MQTT over TLS
  # @see https://github.com/mqtt/mqtt.github.io/wiki/URI-Scheme
  class MQTTS < MQTT
    DEFAULT_PORT = 8883

    def require_deps
      require_relative '../../../patches/openssl'
    end

    # Create a TLS-encrypted socket connection to the MQTT broker
    # @param local_args [Array] Optional local_host and local_port for binding
    # @param ssl_context [OpenSSL::SSL::SSLContext] Pre-configured SSL context (required)
    # @param connect_timeout [Numeric, nil] Timeout in seconds for connection establishment and SSL handshake
    # @param tcp_args [Hash] Additional TCP options (see {MQTT#to_io})
    # @return [OpenSSL::SSL::SSLSocket]
    def to_io(*local_args, ssl_context:, connect_timeout: nil, **tcp_args)
      tcp = super(*local_args, connect_timeout:, **tcp_args)
      OpenSSL::SSL::SSLSocket.new(tcp, ssl_context).tap do |ssl_socket|
        ssl_socket.sync_close = true
        ssl_socket.hostname = host # For SNI validation if requested
        ssl_socket.connect
      end
    end
  end

  # MQTT over Unix domain socket
  # @example
  #   URI('unix:///var/run/mosquitto.sock')
  class Unix < ::URI::Generic
    DEFAULT_PORT = nil

    def require_deps
      require 'socket'
    end

    # Create a Unix domain socket connection
    # @return [UNIXSocket]
    def to_io(...)
      UNIXSocket.new(path)
    end
  end
end

URI.register_scheme 'mqtt', URI::MQTT
URI.register_scheme 'mqtts', URI::MQTTS
URI.register_scheme 'unix', URI::Unix
