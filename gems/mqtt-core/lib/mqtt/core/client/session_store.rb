# frozen_string_literal: true

require_relative 'client_id_generator'

module MQTT
  module Core
    class Client
      # @abstract The session store interface
      # The Session Store is responsible for...
      #  * Keeping track of packet ids and ACK status of packets that we are sending.
      #    These incomplete packets are retried on reconnecting to an established session.
      #  * Meeting the Quality of Service guarantees for received PUBLISH packets.
      class SessionStore
        include ClientIdGenerator

        # @!visibility private
        def self.extract_uri_params(uri_params)
          # amazonq-ignore-next-line
          uri_params.slice(*%w[client_id expiry_interval]).transform_keys(&:to_sym).tap do |params|
            params[:expiry_interval] = Integer(params[:expiry_interval]) if params.key?(:expiry_interval)
          end
        end

        # Raised from PUBLISH or SUBSCRIBE if the session store does not support the requested QoS level
        class QoSNotSupported < Error; end

        # Maximum Session Expiry Interval
        # The spec says this means 'never' expire, but it also equates to 136 years so there is no practical
        # need for special handling.
        MAX_EXPIRY_INTERVAL = 0xFFFFFFFF

        include MQTT::Logger

        # @!attribute [r] expiry_interval
        #  @return [Integer] duration in seconds before the session data expires after disconnect.
        # @note the writer method is api private for MQTT 5.0 sever assigned expiry.
        attr_accessor :expiry_interval

        # @!attribute [r] client_id
        #   @return [String]
        # @note the writer method (if defined in subclass) is ap private for MQTT 5.0 server assigned client id
        attr_reader :client_id

        # @param [String|nil] client_id
        #   * Empty string (default) is a session local anonymous or auto-assigned id (version-dependent handling)
        #   * Explicitly `nil` to generate random id
        #   * Otherwise a valid client_id for the server
        # @param [Integer|nil] expiry_interval
        def initialize(expiry_interval:, client_id:)
          init_client_id(client_id)
          init_expiry_interval(expiry_interval)
        end

        def validate_qos!(requested_qos)
          return if requested_qos <= max_qos

          raise QoSNotSupported, "QoS #{requested_qos} is not supported by #{self.class}"
        end

        # @!method retry_packets
        #   @return [Array<Packet>] the list of unacknowledged packets to resend on re-connect

        # @!method clean?
        #   @return [Boolean] true if reconnection should establish a new session

        # @!method connected!
        #   Connection has been acknowledged server-assigned client_id and expiry_interval are available
        #   @return [void]

        # @!method disconnected!
        #   Connection has been disconnected
        #   @return [void]

        # @!method expired?
        #   @return [Boolean] true if the {expiry_interval} has passed since the latest activity

        # @!method stored_packet?(packet_id)
        #   @param [Integer] packet_id
        #   @return [Boolean] true if the packet_id is in use and waiting acknowledgement

        # @!method store_packet(packet, replace: false)
        #   @param [Packet] packet the packet (with packet_identifier) to store
        #   @param [Boolean] replace allow overwriting of packet_id (part of QOS2 flow)
        #   @return [void]
        #   @raise [KeyError] if packet_id is in use and replace is not true

        # Discard the packet with this packet id
        # @!method release_packet(packet_id)
        #   @param [Integer] packet_id
        #   @return [void]

        # Maximum Quality of Service level supported by this session store
        # @!method max_qos
        #   @return [Integer]

        private

        def init_client_id(client_id)
          client_id ||= generate_client_id
          @client_id = client_id

          return if client_id.length.positive? || allow_server_assigned_client_id?

          raise ArgumentError, "#{self.class} requires a non-empty client id"
        end

        # client id can only be empty if the session store allows server-assigned client ids
        # which it can do by defining a writer for :client_id
        def allow_server_assigned_client_id?
          respond_to?(:client_id=)
        end

        def init_expiry_interval(expiry_interval)
          expiry_interval ||= MAX_EXPIRY_INTERVAL
          unless expiry_interval.between?(0, MAX_EXPIRY_INTERVAL)
            raise ArgumentError, "expiry_interval must be between 0 and #{MAX_EXPIRY_INTERVAL}"
          end

          if expiry_interval.zero? && max_qos.positive?
            raise ArgumentError, "#{self.class} requires a non-zero expiry_interval"
          end

          @expiry_interval = expiry_interval
        end
      end
    end
  end
end
