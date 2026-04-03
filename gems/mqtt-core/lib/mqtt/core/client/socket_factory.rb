# frozen_string_literal: true

require_relative 'uri'
require_relative '../../options'

module MQTT
  module Core
    class Client
      # A Factory for creating the underlying connection to an MQTT server/broker from a URI
      # @see https://github.com/mqtt/mqtt.github.io/wiki/URI-Scheme
      # @api public
      class SocketFactory
        extend Options
        include Options

        # Option keys for constructing a URI
        URI_OPTIONS = %i[uri host port local_addr local_port scheme password_file].freeze

        # Option keys for constructing an IO object.
        # @see new_io
        IO_OPTIONS = (%i[connect_timeout resolv_timeout tcp_nodelay] + [:ssl_context, 'ssl_']).freeze

        # All option keys owned by SocketFactory
        OPTIONS = (%i[ignore_uri_params] + URI_OPTIONS + IO_OPTIONS).freeze

        # Removes {OPTIONS} from an options Hash.
        def self.extract_io_options(options)
          slice_opts!(options, *OPTIONS[..-1], prefix: OPTIONS.last)
        end

        # Create a SocketFactory for establishing MQTT connections
        #
        # @overload create(uri = ENV['MQTT_SERVER'], **opts)
        #   Create from a URI
        #   @param [String, URI] uri an mqtt://, mqtts:// or unix:// URI
        #   @param [Hash<Symbol>] **opts
        #   @option opts [Boolean] ignore_uri_params (false)
        #     URI query parameters are merged into the opts Hash unless this is set. Use where uri input is untrusted.
        #   @option opts [String] password_file Provide authentication password from a file
        #   @option opts [Hash<Symbol>] **io_opts connection timeouts and socket options see {#new_io}
        #   @option opts [OpenSSL::SSL::SSLContext] ssl_context SSL context for `mqtts://` scheme
        #
        #     - A default (secure) context is created if this option is absent and the mqtts:// scheme is used.
        #   @option opts [Hash<Symbol>] **ssl Additional `ssl_(.*)` options passed to
        #     OpenSSL::SSL::SSLContext#set_params
        #
        #     - `min_version`, `ca_file`, `ciphers`, etc...
        #   @option opts [Hash<Symbol>] **client_certificate options for client authentication certificate
        #
        #     - `ssl_cert`, `ssl_key` - can take native `OpenSSL` objects, or construct them from a `String`
        #     - `ssl_cert_file`, `ssl_key_file` - options to construct certificate objects from files
        #     - `ssl_passphrase`, `ssl_passphrase_file` - options to set the passphrase for the private key if required
        #   @return [SocketFactory]
        #   @example MQTT URI
        #     uri = URI('mqtt://localhost:1883')
        #     factory = MQTT::Core::Client::SocketFactory.create(uri)
        #     factory.new_io # => #<TCPSocket:0x00007f9920002000>
        #   @example MQTTS URI with minimum TLS version
        #     uri = URI('mqtts://localhost:8883')
        #     factory = MQTT::Core::Client::SocketFactory.create(uri, ssl_min_version: :TLSv1_2)
        #     factory.new_io # => #<OpenSSL::SSL::SSLSocket:0x00007f9920002000>
        #   @example MQTTS URI with client certificate files
        #     uri = 'mqtts://localhost:8883?ssl_cert_file=client.crt&ssl_key_file=client.key'
        #     factory = MQTT::Core::Client::SocketFactory.create(uri)
        #   @see URI::MQTT
        #   @see URI::MQTTS
        #
        # @overload create(host, port = nil, local_addr = nil, local_port = nil, scheme: nil, **opts)
        #   Build URI from TCP-style arguments
        #   @param [String] host Hostname or IP address
        #   @param [Integer, nil] port Port number
        #   @param [String, nil] local_addr Local address for the TCPSocket
        #   @param [Integer, nil] local_port Local port for the TCPSocket
        #   @param [String, nil] scheme 'mqtt', 'mqtts', or nil to auto-detect from ssl options
        #   @param [Hash<Symbol>] **opts Additional options (see first overload)
        #   @return [SocketFactory]
        #
        # @overload create(**opts)
        #   Create from keyword options only
        #   @param [Hash<Symbol>] opts Options including uri, host, port, local_addr, local_port (see first overload)
        #   @return [SocketFactory]
        #
        # @overload create(klass, *rest, **opts)
        #   Create a custom IO builder
        #   @param [Class] klass Class to instantiate
        #   @param [Array] *rest Arguments passed to klass.new
        #   @param [Hash<Symbol>] **opts Keyword arguments passed to klass.new
        #   @return [:new_io] New instance that implements `#new_io`
        #
        # @overload create(obj, options: {})
        #   Pass through an existing SocketFactory or compatible object
        #   @param [:new_io] obj Object that implements `#new_io`
        #   @param [Hash<Symbol>] options SocketFactory related options are extracted from this hash
        #   @return [:new_io] The obj parameter unchanged
        #   @see extract_io_options
        def self.create(*io_args, options: {}, **opts)
          opts.merge!(extract_io_options(options))
          return io_args.first if io_args.first.respond_to?(:new_io)

          (io_args.first.is_a?(Class) ? io_args.shift : self).new(*io_args, **opts)
        end

        # @!visibility private
        def initialize(*io_args, ignore_uri_params: false, **opts)
          extract_io_args(io_args, opts)

          @uri, @io_args = parse_uri(*io_args, default_scheme: default_scheme(opts))
          unless %w[mqtt mqtts unix].include?(@uri.scheme)
            raise URI::InvalidURIError, "Invalid scheme for MQTT: #{@uri.scheme}"
          end

          @uri.require_deps

          merge_uri_params!(opts) unless ignore_uri_params
          @uri.query = nil

          @io_opts = slice_opts!(opts, :connect_timeout, :resolv_timeout, :tcp_nodelay) do |k, v|
            k == :tcp_nodelay ? coerce_boolean(k, v) : coerce_float(k, v)
          end

          @auth = build_auth(opts)
          @ssl_context = build_ssl_context(**slice_ssl_opts!(opts))

          # Remaining unused opts
          @query_params = opts.freeze
        end
        # @return [URI] The URI that will be used for the next connection.
        attr_reader :uri
        alias sanitized_uri uri

        # @return [Hash<Symbol>] io_opts default options for #new_io
        attr_reader :io_opts

        # @return [Hash<Symbol>] username and password from URI
        attr_reader :auth

        # @return [Hash<Symbol>] Unused options and uri query parameters. This hash is frozen.
        attr_reader :query_params

        # @param [Hash<Symbol>] io_opts Options passed to the underlying IO object
        #
        #    Available options depend on the URI scheme
        # @option io_opts [Boolean] tcp_nodelay (true) (MQTT/S) Enable TCP_NODELAY to avoid trying to coalesce packets.
        # @option io_opts [Numeric] connect_timeout (nil) (MQTT/S) Timeout in seconds to establish a connection
        # @option io_opts [Numeric] resolv_timeout (connect_timeout) (MQTT/S) Timeout in seconds for name resolution
        # @return [IO] -a connection to the URI
        def new_io(**io_opts)
          @uri.to_io(*@io_args, **@io_opts, **io_opts, **(@ssl_context && { ssl_context: @ssl_context }))
        end

        private

        def merge_uri_params!(opts)
          opts.merge!(URI.decode_www_form(@uri.query || '').to_h { |k, v| [k.to_sym, v == '' ? true : v] })
        end

        def default_scheme(io_params)
          return io_params.delete(:scheme) if io_params.key?(:scheme)

          io_params.keys.any? { |k| k.to_s.start_with?('ssl_') } ? 'mqtts' : 'mqtt'
        end

        # Pull non-SSL args out of the hash
        # amazonq-ignore-next-line
        def extract_io_args(io_args, io_params)
          %i[uri host port local_addr local_port].each { |k| io_args << io_params.delete(k) }
          io_args.compact!
        end

        def parse_uri(host = nil, *io_args, default_scheme:)
          host ||= ENV.fetch('MQTT_SERVER', nil)
          return [host, io_args.freeze] if host.is_a?(URI)
          return [URI.parse(host), io_args.freeze] if host.is_a?(String) && host =~ %r{^[a-z]+://}

          port = io_args.shift if io_args.any?
          [URI.parse(["#{default_scheme}://#{host}", port].compact.join(':')), io_args.freeze]
        end

        def build_auth(io_params)
          # agents review - file path traversal
          password = File.read(io_params.delete(:password_file)).chomp if io_params.key?(:password_file)
          password ||= URI.decode_www_form_component(@uri.password) if @uri.password
          username = URI.decode_www_form_component(@uri.user) if @uri.user
          # amazonq-ignore-next-line
          @uri.password = '********' if password
          { username: username, password: password }.compact
        end

        def slice_ssl_opts!(opts, *_keys)
          slice_opts!(opts, :ssl_context, prefix: 'ssl_') do |k, v|
            case k
            when :verify_mode
              coerce_ssl_verify_mode(v)
            when :verify_hostname
              coerce_boolean(k, v)
            when :verify_depth
              coerce_integer(k, v)
            else
              v
            end
          end
        end

        def build_ssl_context(ssl_context: nil, **ssl_params)
          return unless @uri.scheme == 'mqtts'

          (ssl_context || OpenSSL::SSL::SSLContext.new).tap do |ctx|
            build_client_certificate_params(ssl_params)
            ctx.set_params(ssl_params)
          end
        end

        def coerce_ssl_verify_mode(value)
          return value if value.is_a?(Integer)
          return value unless value

          case value.to_s.downcase
          when 'none', '0' then OpenSSL::SSL::VERIFY_NONE
          when 'peer', '1' then OpenSSL::SSL::VERIFY_PEER
          when 'fail_if_no_peer_cert', '2' then OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
          when 'client_once', '4' then OpenSSL::SSL::VERIFY_CLIENT_ONCE
          else
            raise ArgumentError, "Invalid ssl_verify_mode: #{value}. Use 'none', 'peer', (See OpenSSL::SSL::VERIFY_*)"
          end
        end

        # rubocop:disable Metrics/AbcSize
        def build_client_certificate_params(ssl_params)
          passphrase = File.read(ssl_params.delete(:passphrase_file)).chomp if ssl_params.key?(:passphrase_file)
          passphrase = ssl_params.delete(:passphrase) if ssl_params.key?(:passphrase)

          ssl_params[:cert] = load_certificate(ssl_params[:cert]) if ssl_params[:cert].is_a?(String)
          ssl_params[:cert] = load_certificate_file(ssl_params.delete(:cert_file)) if ssl_params.key?(:cert_file)

          ssl_params[:key] = load_private_key(ssl_params[:key], passphrase) if ssl_params[:key].is_a?(String)
          return unless ssl_params.key?(:key_file)

          ssl_params[:key] =
            load_private_key_file(ssl_params.delete(:key_file), passphrase)
        end
        # rubocop:enable Metrics/AbcSize

        def load_certificate_file(cert_file)
          return load_certificate(cert_file.binread) if cert_file.respond_to?(:binread)

          load_certificate(File.binread(cert_file))
        end

        def load_certificate(cert)
          return cert if cert.is_a?(OpenSSL::X509::Certificate)

          OpenSSL::X509::Certificate.new(cert)
        end

        def load_private_key_file(key_file, passphrase = nil)
          return load_private_key(key_file.binread, passphrase) if key_file.respond_to?(:binread)

          load_private_key(File.binread(key_file), passphrase)
        end

        def load_private_key(key, pwd = nil)
          return key if key.is_a?(OpenSSL::PKey::PKey)

          OpenSSL::PKey.read(key, pwd)
        end
      end
    end
  end
end
